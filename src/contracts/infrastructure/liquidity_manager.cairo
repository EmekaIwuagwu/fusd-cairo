#[starknet::contract]
pub mod LiquidityManager {
    use starknet::ContractAddress;
    use fusd::contracts::interfaces::ISNIP2::{ISNIP2Dispatcher, ISNIP2DispatcherTrait};
    use fusd::contracts::interfaces::IProtocol::ILiquidityManager;
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess
    };

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        fusd_token: ContractAddress,
        target_ratios: Map::<(ContractAddress, ContractAddress), u8>, // Pair -> %
        
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccessControlEvent: AccessControlComponent::Event,
        LiquidityAdded: LiquidityAdded,
        LiquidityRemoved: LiquidityRemoved,
        RebalanceExecuted: RebalanceExecuted,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquidityAdded {
        pub dex: ContractAddress,
        pub token_a: ContractAddress,
        pub token_b: ContractAddress,
        pub amount_a: u256,
        pub amount_b: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquidityRemoved {
        pub dex: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RebalanceExecuted {
        pub timestamp: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, fusd: ContractAddress, owner: ContractAddress) {
        self.fusd_token.write(fusd);
        self.access_control.initializer(owner);
    }

    #[abi(embed_v0)]
    impl LiquidityManagerImpl of ILiquidityManager<ContractState> {
        fn add_liquidity(
            ref self: ContractState, 
            dex: ContractAddress, 
            token_other: ContractAddress, 
            amount_fusd: u256, 
            amount_other: u256
        ) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN); 
            
            let fusd = self.fusd_token.read();
            
            ISNIP2Dispatcher { contract_address: fusd }.approve(dex, amount_fusd);
            ISNIP2Dispatcher { contract_address: token_other }.approve(dex, amount_other);
            
            self.emit(LiquidityAdded { dex, token_a: fusd, token_b: token_other, amount_a: amount_fusd, amount_b: amount_other });
        }

        fn rebalance(ref self: ContractState) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
            self.emit(RebalanceExecuted { timestamp: starknet::get_block_timestamp() });
        }
    }
}
