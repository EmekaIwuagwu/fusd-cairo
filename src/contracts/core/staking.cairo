#[starknet::contract]
pub mod Staking {
    use starknet::{ContractAddress, get_caller_address};
    use fusd::contracts::interfaces::ISNIP2::{ISNIP2Dispatcher, ISNIP2DispatcherTrait};
    use fusd::contracts::interfaces::IProtocol::IStaking;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::num::traits::Zero;

    #[storage]
    struct Storage {
        fusd_token: ContractAddress,
        total_staked: u256,
        user_stakes: Map::<ContractAddress, u256>,
        reward_per_token_stored: u256,
        user_reward_per_token_paid: Map::<ContractAddress, u256>,
        rewards: Map::<ContractAddress, u256>,
        last_update_time: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Staked: Staked,
        Withdrawn: Withdrawn,
        RewardPaid: RewardPaid,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Staked {
        #[key]
        pub user: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdrawn {
        #[key]
        pub user: ContractAddress,
        pub amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RewardPaid {
        #[key]
        pub user: ContractAddress,
        pub reward: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, fusd: ContractAddress) {
        self.fusd_token.write(fusd);
    }

    #[abi(embed_v0)]
    impl StakingImpl of IStaking<ContractState> {
        fn stake(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            self._update_reward(get_caller_address());
            
            let fusd = ISNIP2Dispatcher { contract_address: self.fusd_token.read() };
            fusd.transfer_from(get_caller_address(), starknet::get_contract_address(), amount);
            
            let current_stake = self.user_stakes.read(get_caller_address());
            self.user_stakes.write(get_caller_address(), current_stake + amount);
            self.total_staked.write(self.total_staked.read() + amount);
            
            self.emit(Staked { user: get_caller_address(), amount });
        }

        fn withdraw(ref self: ContractState, amount: u256) {
            assert(amount > 0, 'Amount must be > 0');
            let user = get_caller_address();
            let current_stake = self.user_stakes.read(user);
            assert(current_stake >= amount, 'Insufficient stake');
            
            self._update_reward(user);
            
            self.user_stakes.write(user, current_stake - amount);
            self.total_staked.write(self.total_staked.read() - amount);
            
            let fusd = ISNIP2Dispatcher { contract_address: self.fusd_token.read() };
            fusd.transfer(user, amount);
            
            self.emit(Withdrawn { user, amount });
        }

        fn claim_rewards(ref self: ContractState) {
            let user = get_caller_address();
            self._update_reward(user);
            
            let reward = self.rewards.read(user);
            if reward > 0 {
                self.rewards.write(user, 0);
                let fusd = ISNIP2Dispatcher { contract_address: self.fusd_token.read() };
                fusd.transfer(user, reward);
                self.emit(RewardPaid { user, reward });
            }
        }

        fn get_user_stake(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_stakes.read(user)
        }
    }

    #[external(v0)]
    fn notify_reward_amount(ref self: ContractState, reward: u256) {
        let total = self.total_staked.read();
        if total > 0 {
            let current_stored = self.reward_per_token_stored.read();
            self.reward_per_token_stored.write(current_stored + (reward * 1_000_000_000_000_000_000 / total));
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _update_reward(ref self: ContractState, account: ContractAddress) {
            let reward_per_token = self.reward_per_token_stored.read();
            if !account.is_zero() {
                let user_reward = self.rewards.read(account);
                let user_stake = self.user_stakes.read(account);
                let paid = self.user_reward_per_token_paid.read(account);
                
                self.rewards.write(account, user_reward + (user_stake * (reward_per_token - paid) / 1_000_000_000_000_000_000));
                self.user_reward_per_token_paid.write(account, reward_per_token);
            }
        }
    }
}
