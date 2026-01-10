use starknet::ContractAddress;

#[starknet::interface]
pub trait IAccessControl<TContractState> {
    fn has_role(self: @TContractState, role: felt252, account: ContractAddress) -> bool;
    fn grant_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn revoke_role(ref self: TContractState, role: felt252, account: ContractAddress);
    fn renounce_role(ref self: TContractState, role: felt252, account: ContractAddress);
}

#[starknet::component]
pub mod AccessControlComponent {
    use starknet::{ContractAddress, get_caller_address};
    use super::IAccessControl;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    pub struct Storage {
        pub _roles: Map::<(felt252, ContractAddress), bool>,
        pub _admin_role: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RoleGranted: RoleGranted,
        RoleRevoked: RoleRevoked,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RoleGranted {
        pub role: felt252,
        pub account: ContractAddress,
        pub sender: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct RoleRevoked {
        pub role: felt252,
        pub account: ContractAddress,
        pub sender: ContractAddress,
    }

    pub mod Roles {
        pub const ADMIN: felt252 = 'ADMIN';
        pub const MINTER: felt252 = 'MINTER';
        pub const BURNER: felt252 = 'BURNER';
        pub const LIQUIDITY_MANAGER: felt252 = 'LIQUIDITY_MANAGER';
        pub const GOVERNANCE: felt252 = 'GOVERNANCE';
    }

    #[embeddable_as(AccessControlImpl)]
    impl AccessControl<
        TContractState, +HasComponent<TContractState>
    > of IAccessControl<ComponentState<TContractState>> {
        fn has_role(self: @ComponentState<TContractState>, role: felt252, account: ContractAddress) -> bool {
            self._roles.read((role, account))
        }

        fn grant_role(ref self: ComponentState<TContractState>, role: felt252, account: ContractAddress) {
            self._assert_only_role(Roles::ADMIN);
            self._grant_role(role, account);
        }

        fn revoke_role(ref self: ComponentState<TContractState>, role: felt252, account: ContractAddress) {
            self._assert_only_role(Roles::ADMIN);
            self._revoke_role(role, account);
        }

        fn renounce_role(ref self: ComponentState<TContractState>, role: felt252, account: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == account, 'AccessControl: bad renounce');
            self._revoke_role(role, account);
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, admin: ContractAddress) {
            self._grant_role(Roles::ADMIN, admin);
        }

        fn _grant_role(ref self: ComponentState<TContractState>, role: felt252, account: ContractAddress) {
            if !self.has_role(role, account) {
                self._roles.write((role, account), true);
                self.emit(RoleGranted { role, account, sender: get_caller_address() });
            }
        }

        fn _revoke_role(ref self: ComponentState<TContractState>, role: felt252, account: ContractAddress) {
            if self.has_role(role, account) {
                self._roles.write((role, account), false);
                self.emit(RoleRevoked { role, account, sender: get_caller_address() });
            }
        }

        fn _assert_only_role(self: @ComponentState<TContractState>, role: felt252) {
            let caller = get_caller_address();
            assert(self.has_role(role, caller), 'AccessControl: missing role');
        }
    }
}
