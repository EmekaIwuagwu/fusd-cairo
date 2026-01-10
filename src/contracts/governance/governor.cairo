#[starknet::contract]
pub mod Governor {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use fusd::contracts::interfaces::IProtocol::{IGovernor, ITimelockDispatcher, ITimelockDispatcherTrait};
    use fusd::contracts::interfaces::ISNIP2::{ISNIP2Dispatcher, ISNIP2DispatcherTrait};
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess
    };

    #[storage]
    struct Storage {
        fusd_token: ContractAddress,
        timelock: ContractAddress,
        proposal_count: u256,
        proposals: Map::<u256, Proposal>,
        votes: Map::<(u256, ContractAddress), bool>,
        quorum_ratio: u8, // e.g. 10%
    }
    
    #[derive(Drop, Serde, starknet::Store)]
    pub struct Proposal {
        pub id: u256,
        pub proposer: ContractAddress,
        pub target: ContractAddress,
        pub selector: felt252,
        pub eta: u64,
        pub for_votes: u256,
        pub against_votes: u256,
        pub start_time: u64,
        pub end_time: u64,
        pub executed: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ProposalCreated: ProposalCreated,
        VoteCast: VoteCast,
        ActionQueued: ActionQueued,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ProposalCreated {
        pub id: u256,
        pub proposer: ContractAddress,
        pub target: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct VoteCast {
        pub id: u256,
        pub voter: ContractAddress,
        pub support: bool,
        pub weight: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ActionQueued {
        pub id: u256,
        pub eta: u64,
    }

    #[constructor]
    fn constructor(ref self: ContractState, fusd: ContractAddress, timelock: ContractAddress) {
        self.fusd_token.write(fusd);
        self.timelock.write(timelock);
        self.quorum_ratio.write(10); // 10%
    }

    #[abi(embed_v0)]
    impl GovernorImpl of IGovernor<ContractState> {
        fn propose(
            ref self: ContractState,
            target: ContractAddress,
            selector: felt252,
            calldata: Array<felt252>,
            description: felt252
        ) -> u256 {
            let user = get_caller_address();
            let fusd = ISNIP2Dispatcher { contract_address: self.fusd_token.read() };
            assert(fusd.balance_of(user) > 0, 'Must hold FUSD to propose');

            let id = self.proposal_count.read() + 1;
            self.proposal_count.write(id);

            let start = get_block_timestamp();
            let end = start + 86400 * 3; // 3 days voting

            let proposal = Proposal {
                id,
                proposer: user,
                target,
                selector,
                eta: 0,
                for_votes: 0,
                against_votes: 0,
                start_time: start,
                end_time: end,
                executed: false,
            };

            self.proposals.write(id, proposal);
            self.emit(ProposalCreated { id, proposer: user, target });
            id
        }
        
        fn cast_vote(ref self: ContractState, proposal_id: u256, support: bool) {
            let user = get_caller_address();
            let mut proposal = self.proposals.read(proposal_id);
            
            assert(get_block_timestamp() < proposal.end_time, 'Voting ended');
            assert(!self.votes.read((proposal_id, user)), 'Already voted');

            let fusd = ISNIP2Dispatcher { contract_address: self.fusd_token.read() };
            let weight = fusd.balance_of(user);
            assert(weight > 0, 'No voting power');

            if support {
                proposal.for_votes += weight;
            } else {
                proposal.against_votes += weight;
            }

            self.proposals.write(proposal_id, proposal);
            self.votes.write((proposal_id, user), true);
            
            self.emit(VoteCast { id: proposal_id, voter: user, support, weight });
        }
    }

    #[external(v0)]
    fn queue(ref self: ContractState, proposal_id: u256, calldata: Array<felt252>) {
        let mut proposal = self.proposals.read(proposal_id);
        assert(get_block_timestamp() >= proposal.end_time, 'Voting still active');
        assert(proposal.for_votes > proposal.against_votes, 'Proposal rejected');
        
        // Check quorum
        let fusd = ISNIP2Dispatcher { contract_address: self.fusd_token.read() };
        let total = fusd.total_supply();
        let quorum = (total * self.quorum_ratio.read().into()) / 100;
        assert(proposal.for_votes >= quorum, 'Quorum not met');

        let timelock = ITimelockDispatcher { contract_address: self.timelock.read() };
        let eta = get_block_timestamp() + 86400 * 7; // 7 days min delay usually
        
        timelock.queue_transaction(proposal.target, proposal.selector, calldata, eta);
        proposal.eta = eta;
        self.proposals.write(proposal_id, proposal);
        
        self.emit(ActionQueued { id: proposal_id, eta });
    }
}
