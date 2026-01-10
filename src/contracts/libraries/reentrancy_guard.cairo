#[starknet::component]
pub mod ReentrancyGuardComponent {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    pub struct Storage {
        pub _status: felt252,
    }
    
    // 0: Unlocked, 1: Locked
    pub const _NOT_ENTERED: felt252 = 0;
    pub const _ENTERED: felt252 = 1;

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn start(ref self: ComponentState<TContractState>) {
            assert(self._status.read() == _NOT_ENTERED, 'ReentrancyGuard: reentrant');
            self._status.write(_ENTERED);
        }

        fn end(ref self: ComponentState<TContractState>) {
            self._status.write(_NOT_ENTERED);
        }
    }
}
