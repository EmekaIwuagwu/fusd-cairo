#[starknet::contract]
pub mod FUSDToken {
    use starknet::{ContractAddress, get_caller_address};
    use fusd::contracts::interfaces::IFUSD::IFUSD;
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess
    };
    use core::num::traits::Zero;
    
    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        _name: felt252,
        _symbol: felt252,
        _decimals: u8,
        _total_supply: u256,
        _balances: Map::<ContractAddress, u256>,
        _allowances: Map::<(ContractAddress, ContractAddress), u256>,
        _max_supply: u256,
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Transfer: Transfer,
        Approval: Approval,
        AccessControlEvent: AccessControlComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Transfer {
        #[key]
        pub from: ContractAddress,
        #[key]
        pub to: ContractAddress,
        pub value: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Approval {
        #[key]
        pub owner: ContractAddress,
        #[key]
        pub spender: ContractAddress,
        pub value: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_supply: u256,
        recipient: ContractAddress,
        owner: ContractAddress
    ) {
        self._name.write('FUSD');
        self._symbol.write('FUSD');
        self._decimals.write(18);
        self._max_supply.write(1_000_000_000_000_000_000_000_000_000); 

        self.access_control.initializer(owner);
        self._mint(recipient, initial_supply);
    }

    #[abi(embed_v0)]
    impl FUSDTokenImpl of IFUSD<ContractState> {
        fn name(self: @ContractState) -> felt252 {
            self._name.read()
        }

        fn symbol(self: @ContractState) -> felt252 {
            self._symbol.read()
        }

        fn decimals(self: @ContractState) -> u8 {
            self._decimals.read()
        }

        fn total_supply(self: @ContractState) -> u256 {
            self._total_supply.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self._balances.read(account)
        }

        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self._allowances.read((owner, spender))
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn transfer_from(
            ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
        ) -> bool {
            let spender = get_caller_address();
            let current_allowance = self._allowances.read((sender, spender));
            assert(current_allowance >= amount, 'ERC20: low allowance');
            self._approve(sender, spender, current_allowance - amount);
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let caller = get_caller_address();
            self._approve(caller, spender, amount);
            true
        }

        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::MINTER);
            self._mint(to, amount);
        }

        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::BURNER);
            self._burn(from, amount);
        }
        
        fn set_max_supply(ref self: ContractState, new_cap: u256) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::GOVERNANCE);
            self._max_supply.write(new_cap);
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _transfer(ref self: ContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) {
            assert(!sender.is_zero(), 'ERC20: transfer from 0');
            assert(!recipient.is_zero(), 'ERC20: transfer to 0');
            let sender_balance = self._balances.read(sender);
            assert(sender_balance >= amount, 'ERC20: low balance');
            self._balances.write(sender, sender_balance - amount);
            self._balances.write(recipient, self._balances.read(recipient) + amount);
            self.emit(Transfer { from: sender, to: recipient, value: amount });
        }

        fn _approve(ref self: ContractState, owner: ContractAddress, spender: ContractAddress, amount: u256) {
            assert(!owner.is_zero(), 'ERC20: approve from 0');
            assert(!spender.is_zero(), 'ERC20: approve to 0');
            self._allowances.write((owner, spender), amount);
            self.emit(Approval { owner, spender, value: amount });
        }

        fn _mint(ref self: ContractState, account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), 'ERC20: mint to 0');
            let current_supply = self._total_supply.read();
            let max_supply = self._max_supply.read();
            assert(current_supply + amount <= max_supply, 'FUSD: Max supply exceeded');

            self._total_supply.write(current_supply + amount);
            self._balances.write(account, self._balances.read(account) + amount);
            self.emit(Transfer { from: Zero::zero(), to: account, value: amount });
        }

        fn _burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            assert(!account.is_zero(), 'ERC20: burn from 0');
            let account_balance = self._balances.read(account);
            assert(account_balance >= amount, 'ERC20: low balance');
            self._balances.write(account, account_balance - amount);
            self._total_supply.write(self._total_supply.read() - amount);
            self.emit(Transfer { from: account, to: Zero::zero(), value: amount });
        }
    }
}
