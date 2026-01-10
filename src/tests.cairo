#[cfg(test)]
mod tests {
    use starknet::ContractAddress;
    use core::num::traits::Zero;

    #[test]
    fn test_zero_address() {
        let addr: ContractAddress = Zero::zero();
        assert(addr.is_zero(), 'Address should be zero');
    }

    #[test]
    fn test_math_logic() {
        let total_supply: u256 = 1000;
        let diff: u256 = 100; // 10% deviation
        let target: u256 = 1000;
        
        // expansion amount = (total_supply * diff) / (target * 2)
        // (1000 * 100) / (1000 * 2) = 100000 / 2000 = 50
        let mint_amount = (total_supply * diff) / (target * 2);
        assert(mint_amount == 50, 'Expansion math incorrect');
    }
}
