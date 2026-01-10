#[starknet::contract]
pub mod BondToken {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use fusd::contracts::interfaces::IProtocol::IBond;
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess
    };

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        _balances: Map::<ContractAddress, u256>,
        _expiry: Map::<ContractAddress, u64>,
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        BondIssued: BondIssued,
        BondRedeemed: BondRedeemed,
        AccessControlEvent: AccessControlComponent::Event,
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
    fn constructor(ref self: ContractState, owner: ContractAddress) {
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
            let user = get_caller_address();
            let bal = self._balances.read(user);
            let expiry = self._expiry.read(user);
            
            assert(bal >= amount, 'Insufficient bond balance');
            assert(get_block_timestamp() >= expiry, 'Bond not yet matured');
            
            self._balances.write(user, bal - amount);
            self.emit(BondRedeemed { user, amount });
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self._balances.read(account)
        }
    }
}
