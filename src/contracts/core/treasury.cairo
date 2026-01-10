#[starknet::contract]
pub mod Treasury {
    use starknet::ContractAddress;
    use fusd::contracts::interfaces::ISNIP2::{ISNIP2Dispatcher, ISNIP2DispatcherTrait};
    use fusd::contracts::interfaces::IProtocol::ITreasury;
    use fusd::contracts::libraries::access_control::AccessControlComponent;

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccessControlEvent: AccessControlComponent::Event,
        Withdraw: Withdraw,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdraw {
        pub token: ContractAddress,
        pub to: ContractAddress,
        pub amount: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.access_control.initializer(admin);
    }

    #[abi(embed_v0)]
    impl TreasuryImpl of ITreasury<ContractState> {
        fn withdraw_erc20(
            ref self: ContractState, 
            token: ContractAddress, 
            to: ContractAddress, 
            amount: u256
        ) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
            ISNIP2Dispatcher { contract_address: token }.transfer(to, amount);
            self.emit(Withdraw { token, to, amount });
        }

        fn approve_erc20(
            ref self: ContractState,
            token: ContractAddress,
            spender: ContractAddress,
            amount: u256
        ) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
            ISNIP2Dispatcher { contract_address: token }.approve(spender, amount);
        }
    }
}
