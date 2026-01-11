const { RpcProvider, Contract, uint256 } = require('starknet');

async function main() {
    const rpc = 'https://api.cartridge.gg/x/starknet/sepolia';
    const provider = new RpcProvider({ nodeUrl: rpc });
    const accountAddress = '0x07bea8856fe0f34bca2ccce7589c4c4834e4288b3f09f916415d9d14d7882a83';

    // STRK Token Address on Sepolia
    const strkAddress = '0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d';
    // ETH Token Address on Sepolia
    const ethAddress = '0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7';

    const strkAbi = [
        {
            "name": "balanceOf",
            "type": "function",
            "inputs": [{ "name": "account", "type": "felt" }],
            "outputs": [{ "name": "balance", "type": "Uint256" }],
            "stateMutability": "view"
        }
    ];

    const strkContract = new Contract(strkAbi, strkAddress, provider);
    const ethContract = new Contract(strkAbi, ethAddress, provider);

    try {
        const strkBalance = await strkContract.balanceOf(accountAddress, { blockIdentifier: 'latest' });
        const ethBalance = await ethContract.balanceOf(accountAddress, { blockIdentifier: 'latest' });

        console.log('Account:', accountAddress);
        console.log('STRK Balance:', strkBalance);
        console.log('ETH Balance:', ethBalance);
    } catch (err) {
        console.error('Error fetching balance:', err);
    }
}

main();
