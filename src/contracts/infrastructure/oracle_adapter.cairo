#[starknet::contract]
pub mod OracleAdapter {
    use starknet::{ContractAddress, get_block_timestamp};
    use fusd::contracts::interfaces::IOracle::{IOracle, IOracleDispatcher, IOracleDispatcherTrait};
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use fusd::contracts::libraries::pausable::PausableComponent;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::num::traits::Zero;

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        oracle_sources: Map::<u8, ContractAddress>,
        sources_count: u8,
        staleness_threshold: u64,
        max_deviation_bps: u64,
        emergency_oracle: ContractAddress,
        use_emergency: bool,
        
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccessControlEvent: AccessControlComponent::Event,
        PausableEvent: PausableComponent::Event,
        EmergencyOracleUpdated: EmergencyOracleUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EmergencyOracleUpdated {
        pub oracle: ContractAddress,
        pub active: bool,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        oracles: Array<ContractAddress>,
        owner: ContractAddress
    ) {
        self.access_control.initializer(owner);
        let mut i: u8 = 0;
        loop {
            if i >= oracles.len().try_into().unwrap() {
                break;
            }
            self.oracle_sources.write(i, *oracles.at(i.into()));
            i += 1;
        };
        self.sources_count.write(i);
        self.staleness_threshold.write(900);
        self.max_deviation_bps.write(200);
        self.use_emergency.write(false);
    }

    #[abi(embed_v0)]
    impl IOracleImpl of IOracle<ContractState> {
        fn get_price(self: @ContractState, asset: felt252) -> (u256, u64) {
             self.pausable.assert_not_paused();

             if self.use_emergency.read() {
                 let emergency = self.emergency_oracle.read();
                 assert(!emergency.is_zero(), 'Emergency oracle not set');
                 return IOracleDispatcher { contract_address: emergency }.get_price(asset);
             }

             let count = self.sources_count.read();
             let threshold = self.staleness_threshold.read();
             let current_time = get_block_timestamp();
             
             let mut prices = ArrayTrait::<u256>::new();
             let mut valid_count = 0;
             let mut i: u8 = 0;
             
             loop {
                if i >= count { break; }
                let oracle_addr = self.oracle_sources.read(i);
                if !oracle_addr.is_zero() {
                    let dispatcher = IOracleDispatcher { contract_address: oracle_addr };
                    let (price, timestamp) = dispatcher.get_price(asset);
                    
                    if current_time >= timestamp && current_time - timestamp <= threshold {
                        prices.append(price);
                        valid_count += 1;
                    }
                }
                i += 1;
             };
             
             assert(valid_count >= 2, 'Oracle: low valid src');
             
             let sorted = self._sort(prices);
             
             let final_price = if valid_count % 2 == 1 {
                 *sorted.at(valid_count / 2)
             } else {
                 let p1 = *sorted.at((valid_count / 2) - 1);
                 let p2 = *sorted.at(valid_count / 2);
                 (p1 + p2) / 2
             };
             
             let min_p = *sorted.at(0);
             let max_p = *sorted.at(valid_count - 1);
             let dev_bps = ((max_p - min_p) * 10000) / min_p;
             assert(dev_bps <= self.max_deviation_bps.read().into(), 'Oracle: high deviation');
             
             (final_price, current_time)
        }

        fn is_stale(self: @ContractState, timestamp: u64) -> bool {
            let current = get_block_timestamp();
            current - timestamp > self.staleness_threshold.read()
        }

        fn set_staleness_threshold(ref self: ContractState, threshold: u64) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
            self.staleness_threshold.write(threshold);
        }

        fn set_max_deviation_bps(ref self: ContractState, bps: u64) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
            self.max_deviation_bps.write(bps);
        }
    }

    #[external(v0)]
    fn set_emergency_oracle(ref self: ContractState, oracle: ContractAddress, active: bool) {
        self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
        self.emergency_oracle.write(oracle);
        self.use_emergency.write(active);
        self.emit(EmergencyOracleUpdated { oracle, active });
    }

    #[external(v0)]
    fn pause(ref self: ContractState) {
        self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
        self.pausable.pause();
    }

    #[external(v0)]
    fn unpause(ref self: ContractState) {
        self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
        self.pausable.unpause();
    }
    
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _sort(self: @ContractState, mut array: Array<u256>) -> Array<u256> {
             let len = array.len();
             if len <= 1 { return array; }
             
             let mut sorted = ArrayTrait::new();
             let mut remaining = array;
             
             loop {
                 if remaining.len() == 0 { break; }
                 let mut min_idx: usize = 0;
                 let mut min_val = *remaining.at(0);
                 let mut k: usize = 1;
                 loop {
                     if k >= remaining.len() { break; }
                     let v = *remaining.at(k);
                     if v < min_val {
                         min_val = v;
                         min_idx = k;
                     }
                     k += 1;
                 };
                 sorted.append(min_val);
                 
                 let mut next_remaining = ArrayTrait::new();
                 let mut m: usize = 0;
                 loop {
                     if m >= remaining.len() { break; }
                     if m != min_idx {
                         next_remaining.append(*remaining.at(m));
                     }
                     m += 1;
                 };
                 remaining = next_remaining;
             };
             sorted
        }
    }
}
