#[starknet::contract]
pub mod BondAuction {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use fusd::contracts::interfaces::IFUSD::{IFUSDDispatcher, IFUSDDispatcherTrait};
    use fusd::contracts::interfaces::IProtocol::{IBondDispatcher, IBondDispatcherTrait};
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess
    };

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        fusd_token: ContractAddress,
        bond_token: ContractAddress,
        bond_price_discount: u8, // Percentage discount for bond purchases
        auction_active: bool,
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        BondsPurchased: BondsPurchased,
        AuctionStarted: AuctionStarted,
        AuctionEnded: AuctionEnded,
        AccessControlEvent: AccessControlComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BondsPurchased {
        #[key]
        pub user: ContractAddress,
        pub fusd_paid: u256,
        pub bonds_issued: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AuctionStarted {
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct AuctionEnded {
        pub timestamp: u64,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        fusd: ContractAddress,
        bond: ContractAddress,
        owner: ContractAddress
    ) {
        self.fusd_token.write(fusd);
        self.bond_token.write(bond);
        self.bond_price_discount.write(10);
        self.access_control.initializer(owner);
    }

    #[external(v0)]
    fn buy_bonds(ref self: ContractState, fusd_amount: u256) {
        assert(self.auction_active.read(), 'Auction not active');
        let user = get_caller_address();
        
        let fusd = IFUSDDispatcher { contract_address: self.fusd_token.read() };
        fusd.transfer_from(user, starknet::get_contract_address(), fusd_amount);
        
        // Burn the FUSD to contract supply
        fusd.burn(starknet::get_contract_address(), fusd_amount);
        
        // Issue bonds (1 FUSD = 1 / (1 - discount) Bonds)
        let discount = self.bond_price_discount.read();
        let bond_amount = (fusd_amount * 100) / (100 - discount.into());
        
        let bond = IBondDispatcher { contract_address: self.bond_token.read() };
        bond.issue(user, bond_amount, get_block_timestamp() + 2592000);
        
        self.emit(BondsPurchased { user, fusd_paid: fusd_amount, bonds_issued: bond_amount });
    }

    #[external(v0)]
    fn start_auction(ref self: ContractState) {
        self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
        self.auction_active.write(true);
        self.emit(AuctionStarted { timestamp: get_block_timestamp() });
    }

    #[external(v0)]
    fn end_auction(ref self: ContractState) {
        self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
        self.auction_active.write(false);
        self.emit(AuctionEnded { timestamp: get_block_timestamp() });
    }
}
