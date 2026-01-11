#[starknet::contract]
pub mod Paymaster {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, get_tx_info};
    use fusd::contracts::interfaces::ISNIP2::{ISNIP2Dispatcher, ISNIP2DispatcherTrait};
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        fusd_token: ContractAddress,
        fusd_to_strk_rate: u256, 
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccessControlEvent: AccessControlComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, fusd: ContractAddress, initial_rate: u256, owner: ContractAddress) {
        self.fusd_token.write(fusd);
        self.fusd_to_strk_rate.write(initial_rate);
        self.access_control.initializer(owner);
    }
    
    #[abi(embed_v0)]
    impl PaymasterImpl of fusd::contracts::interfaces::IPaymaster::IPaymaster<ContractState> {
        fn validate_and_pay_fee(ref self: ContractState, user_limit: u256) {
            let tx_info = get_tx_info().unbox();
            let max_fee = tx_info.max_fee; 
            let sender = tx_info.account_contract_address; 
            
            let fusd_needed = self._convert_strk_to_fusd(max_fee.into());
            
            assert(fusd_needed <= user_limit, 'Paymaster: limit exceeded');

            let fusd = ISNIP2Dispatcher { contract_address: self.fusd_token.read() };
            fusd.transfer_from(sender, get_contract_address(), fusd_needed);
        }
        
        fn set_rate(ref self: ContractState, new_rate: u256) {
            self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
            self.fusd_to_strk_rate.write(new_rate);
        }
    }
    
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _convert_strk_to_fusd(self: @ContractState, strk_amount: u256) -> u256 {
            let rate = self.fusd_to_strk_rate.read();
            (strk_amount * rate) / 1_000_000_000_000_000_000
        }
    }
}
