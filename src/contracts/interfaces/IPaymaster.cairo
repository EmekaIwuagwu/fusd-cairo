#[starknet::interface]
pub trait IPaymaster<TContractState> {
    fn validate_and_pay_fee(ref self: TContractState, user_limit: u256);
    fn set_rate(ref self: TContractState, new_rate: u256);
}
