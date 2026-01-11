#[starknet::interface]
pub trait IPausable<TContractState> {
    fn is_paused(self: @TContractState) -> bool;
}

#[starknet::component]
pub mod PausableComponent {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    pub struct Storage {
        pub _paused: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Paused: Paused,
        Unpaused: Unpaused,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Paused {
        pub account: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Unpaused {
        pub account: ContractAddress,
    }

    #[embeddable_as(PausableImpl)]
    impl Pausable<
        TContractState, +HasComponent<TContractState>
    > of super::IPausable<ComponentState<TContractState>> {
        fn is_paused(self: @ComponentState<TContractState>) -> bool {
            self._paused.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn pause(ref self: ComponentState<TContractState>) {
            assert(!self._paused.read(), 'Pausable: already paused');
            self._paused.write(true);
            self.emit(Paused { account: get_caller_address() });
        }

        fn unpause(ref self: ComponentState<TContractState>) {
            assert(self._paused.read(), 'Pausable: not paused');
            self._paused.write(false);
            self.emit(Unpaused { account: get_caller_address() });
        }

        fn assert_not_paused(self: @ComponentState<TContractState>) {
            assert(!self._paused.read(), 'Pausable: paused');
        }

        fn assert_paused(self: @ComponentState<TContractState>) {
            assert(self._paused.read(), 'Pausable: not paused');
        }
    }
}
