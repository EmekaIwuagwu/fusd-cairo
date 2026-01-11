#[starknet::contract]
pub mod MonetaryPolicy {
    use starknet::{ContractAddress, get_block_timestamp};
    use fusd::contracts::interfaces::IFUSD::{IFUSDDispatcher, IFUSDDispatcherTrait};
    use fusd::contracts::interfaces::IOracle::{IOracleDispatcher, IOracleDispatcherTrait};
    use fusd::contracts::interfaces::IProtocol::{
        IMonetaryPolicy, IPausable, IBondAuctionDispatcher, IBondAuctionDispatcherTrait,
        IStakingDispatcher, IStakingDispatcherTrait
    };
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

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
        
        last_rebase_time: u64,
        epoch_duration: u64,
        
        max_supply_cap: u256,
        
        paused: bool,
        
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        RebaseOperation: RebaseOperation,
        AccessControlEvent: AccessControlComponent::Event,
        Paused: Paused,
        Unpaused: Unpaused,
        SupplyCapUpdated: SupplyCapUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RebaseOperation {
        pub epoch: u64,
        pub price: u256,
        pub supply_delta: i128,
        pub timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Paused {
        pub account: ContractAddress,
    }
    
    #[derive(Drop, starknet::Event)]
    pub struct Unpaused {
        pub account: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SupplyCapUpdated {
        pub old_cap: u256,
        pub new_cap: u256,
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
        self.epoch_duration.write(21600); 
        self.max_supply_cap.write(100_000_000_000_000_000_000_000); // 100k cap for testnet
        self.paused.write(false);
        
        self.access_control.initializer(owner);
    }
    
    #[abi(embed_v0)]
    impl MonetaryPolicyImpl of IMonetaryPolicy<ContractState> {
        fn rebase(ref self: ContractState) {
            assert(!self.paused.read(), 'MonetaryPolicy: Paused');
            
            let current_time = get_block_timestamp();
            let last_rebase = self.last_rebase_time.read();
            // Stricter cooldown check: at least 1 epoch duration must pass
            assert(current_time >= last_rebase + self.epoch_duration.read(), 'MonetaryPolicy: Cooldown');
            
            let oracle_dispatcher = IOracleDispatcher { contract_address: self.oracle.read() };
            let (current_price, price_timestamp) = oracle_dispatcher.get_price('FUSD/USD');
            
            assert(!oracle_dispatcher.is_stale(price_timestamp), 'MonetaryPolicy: Stale price');
            
            let target = self.target_price.read();
            let threshold = self.deviation_threshold.read();
            
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
            self.emit(RebaseOperation {
                epoch: current_time / self.epoch_duration.read(),
                price: current_price,
                supply_delta: supply_delta,
                timestamp: current_time
            });
        }

        fn set_paused(ref self: ContractState, paused: bool) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN); 
            self._set_paused(paused);
        }
    }

    #[abi(embed_v0)]
    impl PausableImpl of IPausable<ContractState> {
        fn pause(ref self: ContractState) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN); 
            self._set_paused(true);
        }
        fn unpause(ref self: ContractState) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN); 
            self._set_paused(false);
        }
        fn is_paused(self: @ContractState) -> bool {
            self.paused.read()
        }
    }
    
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _set_paused(ref self: ContractState, paused: bool) {
            self.paused.write(paused);
            if paused {
                self.emit(Paused { account: starknet::get_caller_address() });
            } else {
                self.emit(Unpaused { account: starknet::get_caller_address() });
            }
        }

        fn _expand(ref self: ContractState, price: u256, target: u256) {
            let fusd = IFUSDDispatcher { contract_address: self.fusd_token.read() };
            let total_supply = fusd.total_supply();
            let max_cap = self.max_supply_cap.read();
            
            if total_supply >= max_cap { return; }

            let diff = price - target;
            let mut mint_amount = (total_supply * diff) / (target * 2);
            
            let cap = total_supply / 50; 
            if mint_amount > cap { mint_amount = cap; }
            
            // Further cap by maximum supply
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
