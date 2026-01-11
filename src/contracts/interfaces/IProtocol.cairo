use starknet::ContractAddress;

#[starknet::interface]
pub trait IMonetaryPolicy<TContractState> {
    fn rebase(ref self: TContractState);
    fn set_paused(ref self: TContractState, paused: bool);
}

#[starknet::interface]
pub trait ITreasury<TContractState> {
    fn withdraw_erc20(ref self: TContractState, token: ContractAddress, to: ContractAddress, amount: u256);
    fn approve_erc20(ref self: TContractState, token: ContractAddress, spender: ContractAddress, amount: u256);
}

#[starknet::interface]
pub trait ILiquidityManager<TContractState> {
    fn add_liquidity(ref self: TContractState, dex: ContractAddress, token_other: ContractAddress, amount_fusd: u256, amount_other: u256);
    fn rebalance(ref self: TContractState);
}

#[starknet::interface]
pub trait ITimelock<TContractState> {
    fn queue_transaction(ref self: TContractState, target: ContractAddress, selector: felt252, calldata: Array<felt252>, eta: u64) -> felt252;
    fn execute_transaction(ref self: TContractState, target: ContractAddress, selector: felt252, calldata: Array<felt252>, eta: u64);
}

#[starknet::interface]
pub trait IGovernor<TContractState> {
    fn propose(ref self: TContractState, target: ContractAddress, selector: felt252, calldata: Array<felt252>, description: felt252) -> u256;
    fn cast_vote(ref self: TContractState, proposal_id: u256, support: bool);
}

#[starknet::interface]
pub trait IStaking<TContractState> {
    fn stake(ref self: TContractState, amount: u256);
    fn withdraw(ref self: TContractState, amount: u256);
    fn claim_rewards(ref self: TContractState, min_reward_amount: u256);
    fn get_user_stake(self: @TContractState, user: ContractAddress) -> u256;
    fn notify_reward_amount(ref self: TContractState, amount: u256);
}

#[starknet::interface]
pub trait IBond<TContractState> {
    fn issue(ref self: TContractState, recipient: ContractAddress, amount: u256, expiry: u64);
    fn redeem(ref self: TContractState, amount: u256);
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IPausable<TContractState> {
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn is_paused(self: @TContractState) -> bool;
}

#[starknet::interface]
pub trait IBondAuction<TContractState> {
    fn buy_bonds(ref self: TContractState, fusd_amount: u256);
    fn start_auction(ref self: TContractState);
    fn end_auction(ref self: TContractState);
}
