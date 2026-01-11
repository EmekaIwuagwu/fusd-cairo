

#[starknet::interface]
pub trait IReentrancyGuard<TContractState> {
    fn is_entered(self: @TContractState) -> bool;
}

#[starknet::component]
pub mod ReentrancyGuardComponent {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    pub struct Storage {
        pub _entered: bool,
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn start(ref self: ComponentState<TContractState>) {
            assert(!self._entered.read(), 'ReentrancyGuard: reentrant call');
            self._entered.write(true);
        }

        fn end(ref self: ComponentState<TContractState>) {
            self._entered.write(false);
        }
    }

    #[embeddable_as(ReentrancyGuardImpl)]
    impl ReentrancyGuard<
        TContractState, +HasComponent<TContractState>
    > of super::IReentrancyGuard<ComponentState<TContractState>> {
        fn is_entered(self: @ComponentState<TContractState>) -> bool {
            self._entered.read()
        }
    }
}
