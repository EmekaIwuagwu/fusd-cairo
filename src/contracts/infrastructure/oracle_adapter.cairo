#[starknet::contract]
pub mod OracleAdapter {
    use starknet::{ContractAddress, get_block_timestamp};
    use fusd::contracts::interfaces::IOracle::{IOracle, IOracleDispatcher, IOracleDispatcherTrait};
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::num::traits::Zero;

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        oracle_sources: Map::<u8, ContractAddress>, // 0, 1, 2
        sources_count: u8,
        staleness_threshold: u64, // e.g. 15 mins (900 sec)
        max_deviation_bps: u64, // 200 bps (2%)
        
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccessControlEvent: AccessControlComponent::Event,
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
    }

    #[abi(embed_v0)]
    impl IOracleImpl of IOracle<ContractState> {
        fn get_price(self: @ContractState, asset: felt252) -> (u256, u64) {
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
                    
                    if current_time - timestamp <= threshold {
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
    
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _sort(self: @ContractState, array: Array<u256>) -> Array<u256> {
             let len = array.len();
             let mut sorted = ArrayTrait::new();
             if len == 0 { return sorted; }
             if len == 1 { 
                 sorted.append(*array.at(0));
                 return sorted;
             }
             if len == 2 {
                 let a = *array.at(0);
                 let b = *array.at(1);
                 if a <= b { sorted.append(a); sorted.append(b); }
                 else { sorted.append(b); sorted.append(a); }
                 return sorted;
             }
             if len >= 3 {
                 let a = *array.at(0);
                 let b = *array.at(1);
                 let c = *array.at(2);
                 if a <= b && b <= c { sorted.append(a); sorted.append(b); sorted.append(c); }
                 else if a <= c && c <= b { sorted.append(a); sorted.append(c); sorted.append(b); }
                 else if b <= a && a <= c { sorted.append(b); sorted.append(a); sorted.append(c); }
                 else if b <= c && c <= a { sorted.append(b); sorted.append(c); sorted.append(a); }
                 else if c <= a && a <= b { sorted.append(c); sorted.append(a); sorted.append(b); }
                 else { sorted.append(c); sorted.append(b); sorted.append(a); }
                 return sorted;
             }
             sorted
        }
    }
}
