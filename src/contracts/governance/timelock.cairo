#[starknet::contract]
pub mod Timelock {
    use starknet::{ContractAddress, get_block_timestamp, syscalls::call_contract_syscall};
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use fusd::contracts::interfaces::IProtocol::ITimelock;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::hash::HashStateTrait;

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        queued_transactions: Map::<felt252, u64>, // tx_hash -> valid_after_timestamp
        min_delay: u64, // e.g. 7 days
        
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccessControlEvent: AccessControlComponent::Event,
        QueueTransaction: QueueTransaction,
        ExecuteTransaction: ExecuteTransaction,
    }

    #[derive(Drop, starknet::Event)]
    pub struct QueueTransaction {
        pub tx_hash: felt252,
        pub target: ContractAddress,
        pub selector: felt252,
        pub eta: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ExecuteTransaction {
        pub tx_hash: felt252,
        pub target: ContractAddress,
        pub selector: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, delay: u64, admin: ContractAddress) {
        self.min_delay.write(delay);
        self.access_control.initializer(admin);
    }
    
    #[abi(embed_v0)]
    impl TimelockImpl of ITimelock<ContractState> {
        fn queue_transaction(
            ref self: ContractState,
            target: ContractAddress,
            selector: felt252,
            calldata: Array<felt252>,
            eta: u64
        ) -> felt252 {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN); 
            
            let current = get_block_timestamp();
            assert(eta >= current + self.min_delay.read(), 'Timelock: Delay not met');
            
            let tx_hash = self._get_tx_hash(target, selector, calldata.span(), eta);
            self.queued_transactions.write(tx_hash, eta);
            
            self.emit(QueueTransaction { tx_hash, target, selector, eta });
            tx_hash
        }

        fn execute_transaction(
            ref self: ContractState,
            target: ContractAddress,
            selector: felt252,
            calldata: Array<felt252>,
            eta: u64
        ) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN); 
            
            let tx_hash = self._get_tx_hash(target, selector, calldata.span(), eta);
            let valid_after = self.queued_transactions.read(tx_hash);
            
            assert(valid_after != 0, 'Timelock: Not queued');
            assert(get_block_timestamp() >= valid_after, 'Timelock: Time not passed');
            
            self.queued_transactions.write(tx_hash, 0); 
            
            call_contract_syscall(target, selector, calldata.span()).unwrap();
            
            self.emit(ExecuteTransaction { tx_hash, target, selector });
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _get_tx_hash(self: @ContractState, target: ContractAddress, selector: felt252, calldata: Span<felt252>, eta: u64) -> felt252 {
             let mut state = core::poseidon::PoseidonTrait::new();
             let target_felt: felt252 = target.into(); 
             state = state.update(target_felt);
             state = state.update(selector);
             state = state.update(eta.into());
             state.finalize()
        }
    }
}
