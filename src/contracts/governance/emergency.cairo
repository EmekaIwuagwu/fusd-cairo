#[starknet::contract]
pub mod Emergency {
    use starknet::ContractAddress;
    use fusd::contracts::libraries::access_control::AccessControlComponent;
    use fusd::contracts::interfaces::IProtocol::{IPausableDispatcher, IPausableDispatcherTrait};

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);

    #[abi(embed_v0)]
    impl AccessControlImpl = AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        AccessControlEvent: AccessControlComponent::Event,
        EmergencyAction: EmergencyAction,
    }

    #[derive(Drop, starknet::Event)]
    pub struct EmergencyAction {
        pub action: felt252,
        pub target: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, admin: ContractAddress) {
        self.access_control.initializer(admin);
    }
    
    #[external(v0)]
    fn trigger_pause(ref self: ContractState, target: ContractAddress) {
        self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
        IPausableDispatcher { contract_address: target }.pause();
        self.emit(EmergencyAction { action: 'PAUSED', target });
    }
    
    #[external(v0)]
    fn trigger_unpause(ref self: ContractState, target: ContractAddress) {
        self.access_control._assert_only_role(AccessControlComponent::Roles::ADMIN);
        IPausableDispatcher { contract_address: target }.unpause();
        self.emit(EmergencyAction { action: 'UNPAUSED', target });
    }
}
