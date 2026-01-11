#[starknet::contract]
pub mod MonetaryPolicy {
    use starknet::{ContractAddress, get_block_timestamp, get_block_number};
    use fusd::contracts::interfaces::IFUSD::{IFUSDDispatcher, IFUSDDispatcherTrait};
    use fusd::contracts::interfaces::IOracle::{IOracleDispatcher, IOracleDispatcherTrait};
    use fusd::contracts::interfaces::IProtocol::{
        IMonetaryPolicy, IBondAuctionDispatcher, IBondAuctionDispatcherTrait,
        IStakingDispatcher, IStakingDispatcherTrait
    };
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use fusd::contracts::libraries::pausable::PausableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

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
        oracle: ContractAddress,
        treasury: ContractAddress,
        liquidity_manager: ContractAddress,
        staking_contract: ContractAddress,
        bond_token: ContractAddress,
        bond_auction: ContractAddress,
        
        target_price: u256,
        deviation_threshold: u256,
        circuit_breaker_threshold: u256, 
        
        last_rebase_time: u64,
        last_rebase_block: u64,
        epoch_duration: u64,
        min_rebase_blocks: u64,
        
        max_supply_cap: u256,
        
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RebaseOperation: RebaseOperation,
        AccessControlEvent: AccessControlComponent::Event,
        PausableEvent: PausableComponent::Event,
        SupplyCapUpdated: SupplyCapUpdated,
        CircuitBreakerTriggered: CircuitBreakerTriggered,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RebaseOperation {
        pub epoch: u64,
        pub price: u256,
        pub supply_delta: i128,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SupplyCapUpdated {
        pub old_cap: u256,
        pub new_cap: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct CircuitBreakerTriggered {
        pub price: u256,
        pub target: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        fusd_address: ContractAddress,
        oracle_address: ContractAddress,
        treasury_address: ContractAddress,
        liquidity_manager_address: ContractAddress,
        staking_address: ContractAddress,
        bond_address: ContractAddress,
        bond_auction_address: ContractAddress,
        owner: ContractAddress
    ) {
        self.fusd_token.write(fusd_address);
        self.oracle.write(oracle_address);
        self.treasury.write(treasury_address);
        self.liquidity_manager.write(liquidity_manager_address);
        self.staking_contract.write(staking_address);
        self.bond_token.write(bond_address);
        self.bond_auction.write(bond_auction_address);
        
        self.target_price.write(1_000_000_000_000_000_000); 
        self.deviation_threshold.write(20_000_000_000_000_000); 
        self.circuit_breaker_threshold.write(200_000_000_000_000_000); 
        self.epoch_duration.write(21600); 
        self.min_rebase_blocks.write(100);
        self.max_supply_cap.write(1_000_000_000_000_000_000_000_000); 
        
        self.access_control.initializer(owner);
    }
    
    #[abi(embed_v0)]
    impl MonetaryPolicyImpl of IMonetaryPolicy<ContractState> {
        fn rebase(ref self: ContractState) {
            self.pausable.assert_not_paused();
            
            let current_time = get_block_timestamp();
            let current_block = get_block_number();
            let last_rebase_t = self.last_rebase_time.read();
            let last_rebase_b = self.last_rebase_block.read();
            
            assert(current_time >= last_rebase_t + self.epoch_duration.read(), 'Cooldown: Time');
            assert(current_block >= last_rebase_b + self.min_rebase_blocks.read(), 'Cooldown: Block');
            
            let oracle_dispatcher = IOracleDispatcher { contract_address: self.oracle.read() };
            let (current_price, price_timestamp) = oracle_dispatcher.get_price('FUSD/USD');
            
            assert(!oracle_dispatcher.is_stale(price_timestamp), 'MonetaryPolicy: Stale price');
            
            let target = self.target_price.read();
            let threshold = self.deviation_threshold.read();
            let cb_threshold = self.circuit_breaker_threshold.read();
            
            let diff = if current_price > target { current_price - target } else { target - current_price };
            if diff > cb_threshold {
                self.pausable.pause();
                self.emit(CircuitBreakerTriggered { price: current_price, target });
                return;
            }

            let mut supply_delta: i128 = 0;

            if current_price > target + threshold {
                 self._expand(current_price, target);
                 supply_delta = 1; 
            } else if current_price < target - threshold {
                 self._contract(current_price, target);
                 supply_delta = -1;
            } else {
                 IBondAuctionDispatcher { contract_address: self.bond_auction.read() }.end_auction();
            }

            self.last_rebase_time.write(current_time);
            self.last_rebase_block.write(current_block);
            self.emit(RebaseOperation {
                epoch: current_time / self.epoch_duration.read(),
                price: current_price,
                supply_delta: supply_delta,
                timestamp: current_time
            });
        }

        fn set_paused(ref self: ContractState, paused: bool) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN); 
            if paused { self.pausable.pause(); } else { self.pausable.unpause(); }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _expand(ref self: ContractState, price: u256, target: u256) {
            let fusd = IFUSDDispatcher { contract_address: self.fusd_token.read() };
            let total_supply = fusd.total_supply();
            let max_cap = self.max_supply_cap.read();
            
            if total_supply >= max_cap { return; }

            let diff = price - target;
            let mut mint_amount = (total_supply * diff) / (target * 2);
            
            let cap = total_supply / 50; 
            if mint_amount > cap { mint_amount = cap; }
            
            if total_supply + mint_amount > max_cap {
                mint_amount = max_cap - total_supply;
            }

            if mint_amount == 0 { return; }
            
            let lp_share = mint_amount / 2;
            let treasury_share = (mint_amount * 3) / 10;
            let staking_share = mint_amount - lp_share - treasury_share;
            
            if lp_share > 0 { fusd.mint(self.liquidity_manager.read(), lp_share); }
            if treasury_share > 0 { fusd.mint(self.treasury.read(), treasury_share); }
            
            if staking_share > 0 { 
                let staking_addr = self.staking_contract.read();
                fusd.mint(staking_addr, staking_share); 
                IStakingDispatcher { contract_address: staking_addr }.notify_reward_amount(staking_share);
            }

            IBondAuctionDispatcher { contract_address: self.bond_auction.read() }.end_auction();
        }

        fn _contract(ref self: ContractState, price: u256, target: u256) {
             IBondAuctionDispatcher { contract_address: self.bond_auction.read() }.start_auction();
        }
    }

    #[external(v0)]
    fn update_supply_cap(ref self: ContractState, new_cap: u256) {
        self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
        let old_cap = self.max_supply_cap.read();
        self.max_supply_cap.write(new_cap);
        self.emit(SupplyCapUpdated { old_cap, new_cap });
    }
}
