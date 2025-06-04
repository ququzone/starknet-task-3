#[starknet::interface]
trait ISNCat<TContractState> {
    fn price(self: @TContractState) -> u256;

    fn buy(ref self: TContractState);
    fn withdraw(ref self: TContractState);
}

#[starknet::contract]
pub mod SNCat {
    use starknet::event::EventEmitter;
use core::num::traits::Zero;
use starknet::storage::StoragePointerReadAccess;
use ERC721Component::InternalTrait;
use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{StorableStoragePointerReadAccess, StoragePointerWriteAccess};
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_token::erc20::interface::{IERC20CamelDispatcher, IERC20CamelDispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_token::erc721::{ERC721Component, extensions::ERC721EnumerableComponent};
    use super::ISNCat;

    pub mod Errors {
        pub const ZERO_PRICE: felt252 = 'Zero price';
        pub const ZERO_ADDRESS: felt252 = 'Zero contract address';
    }

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);

    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721MixinImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    component!(path: ERC721EnumerableComponent, storage: erc721_enumerable, event: ERC721EnumerableEvent);

    #[abi(embed_v0)]
    impl ERC721EnumerableImpl = ERC721EnumerableComponent::ERC721EnumerableImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = ERC721EnumerableComponent::InternalImpl<ContractState>;

    #[storage]
    pub struct Storage {
        strk_dispatcher: IERC20CamelDispatcher,
        price: u256,
        token_id: u256,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        erc721_enumerable: ERC721EnumerableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        ERC721EnumerableEvent: ERC721EnumerableComponent::Event,
        Bought: Bought,
    }

    #[derive(Drop, Debug, PartialEq, starknet::Event)]
    pub struct Bought {
        pub account: ContractAddress,
        pub token_id: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_owner: ContractAddress, strk_address: ContractAddress, initial_price: u256) {
        assert(!initial_owner.is_zero(), Errors::ZERO_ADDRESS);
        assert(!strk_address.is_zero(), Errors::ZERO_ADDRESS);
        assert(initial_price > 0, Errors::ZERO_PRICE);

        self.ownable.initializer(initial_owner);
        self.strk_dispatcher.write(IERC20CamelDispatcher { contract_address: strk_address });
        self.erc721.initializer("Starknet Cat", "SNCAT", "https://api.example.com/v1/");
        self.erc721_enumerable.initializer();
        self.price.write(initial_price);
        self.token_id.write(0);
    }

    #[abi(embed_v0)]
    impl SNCatImpl of ISNCat<ContractState> {
        fn price(self: @ContractState) -> u256 {
            self.price.read()
        }

        fn buy(ref self: ContractState) {
            let success = self.strk_dispatcher.read().transferFrom(get_caller_address(), get_contract_address(), self.price.read());
            assert(success, 'Transfer fee failed');

            let token_id = self.token_id.read() + 1;
            let owner = get_caller_address();

            self.erc721.mint(owner, token_id);
            self.token_id.write(token_id);

            self.emit(Bought {
                account: owner,
                token_id: token_id,
            });
        }

        fn withdraw(ref self: ContractState) {
            self.ownable.assert_only_owner();
            let strk_dispatcher = self.strk_dispatcher.read();
            let success = strk_dispatcher.transfer(get_caller_address(), strk_dispatcher.balanceOf(get_contract_address()));
            assert(success, 'Withdraw fee failed');
        }
    }

    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress
        ) {
            let mut contract_state = self.get_contract_mut();
            contract_state.erc721_enumerable.before_update(to, token_id);
        }
    }
}
