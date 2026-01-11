#[starknet::contract]
pub mod BondToken {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use fusd::contracts::interfaces::IProtocol::IBond;
    use fusd::contracts::interfaces::ISNIP2::{ISNIP2Dispatcher, ISNIP2DispatcherTrait};
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use fusd::contracts::libraries::pausable::PausableComponent;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess, StoragePointerWriteAccess
    };

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
        fusd_token: ContractAddress,
        _balances: Map::<ContractAddress, u256>,
        _expiry: Map::<ContractAddress, u64>,
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        BondIssued: BondIssued,
        BondRedeemed: BondRedeemed,
        AccessControlEvent: AccessControlComponent::Event,
        PausableEvent: PausableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BondIssued {
        #[key]
        pub recipient: ContractAddress,
        pub amount: u256,
        pub expiry: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BondRedeemed {
        #[key]
        pub user: ContractAddress,
        pub amount: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, fusd: ContractAddress, owner: ContractAddress) {
        self.fusd_token.write(fusd);
        self.access_control.initializer(owner);
    }

    #[abi(embed_v0)]
    impl BondImpl of IBond<ContractState> {
        fn issue(ref self: ContractState, recipient: ContractAddress, amount: u256, expiry: u64) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::MINTER);
            
            let current_bal = self._balances.read(recipient);
            self._balances.write(recipient, current_bal + amount);
            self._expiry.write(recipient, expiry);
            
            self.emit(BondIssued { recipient, amount, expiry });
        }

        fn redeem(ref self: ContractState, amount: u256) {
            self.pausable.assert_not_paused();
            let user = get_caller_address();
            let bal = self._balances.read(user);
            let expiry = self._expiry.read(user);
            
            assert(bal >= amount, 'Insufficient bond balance');
            assert(get_block_timestamp() >= expiry, 'Bond not yet matured');
            
            self._balances.write(user, bal - amount);
            
            let fusd = fusd::contracts::interfaces::IFUSD::IFUSDDispatcher { contract_address: self.fusd_token.read() };
            fusd::contracts::interfaces::IFUSD::IFUSDDispatcherTrait::mint(fusd, user, amount);
            
            self.emit(BondRedeemed { user, amount });
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self._balances.read(account)
        }
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
}
