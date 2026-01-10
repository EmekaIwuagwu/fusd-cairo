#[starknet::interface]
pub trait IOracle<TContractState> {
    fn get_price(self: @TContractState, asset: felt252) -> (u256, u64);
    fn is_stale(self: @TContractState, timestamp: u64) -> bool;
}
