const { Account, RpcProvider } = require('starknet');

async function main() {
    const rpc = 'https://api.cartridge.gg/x/starknet/sepolia';
    const provider = new RpcProvider({ nodeUrl: rpc });

    // Explicitly use 'latest' for any default block queries if possible, 
    // but we will fetch nonce manually.

    const accountAddress = '0x07bea8856fe0f34bca2ccce7589c4c4834e4288b3f09f916415d9d14d7882a83';
    const privateKey = '0x02e9953827beae10fdae64b9a0f11e99ab47fd904736f8dee242fe1663d24fe0';
    const account = new Account(provider, accountAddress, privateKey);

    console.log('Account connected:', accountAddress);

    // Fetch Nonce from LATEST block (avoid pending)
    try {
        console.log('Fetching nonce from latest block...');
        const nonce = await provider.getNonceForAddress(accountAddress, 'latest');
        console.log('Nonce:', nonce);

        const classHash = "0x033c556ffe029738d5769a471113887550b395f93225c2f1d47c7daee05c5264";
        const constructorCalldata = [
            "1000000000000000000", "0",
            accountAddress,
            accountAddress
        ];

        console.log('Deploying FUSD Token...');
        const deployResponse = await account.deployContract({
            classHash: classHash,
            constructorCalldata: constructorCalldata
        }, {
            nonce: nonce, // Verify if this works
            resourceBounds: {
                l2_gas: { max_amount: '0x1e8480', max_price_per_unit: '0x1' },
                l1_gas: { max_amount: '0x13880', max_price_per_unit: '0x2540be400' }
            }
        });

        console.log('Deploy Tx:', deployResponse.transaction_hash);
        console.log('Contract Address:', deployResponse.contract_address);
        console.log('Waiting for confirmation...');
        await provider.waitForTransaction(deployResponse.transaction_hash);
        console.log('Deployment Complete! 🚀');
    } catch (err) {
        console.error('Failed:', err);
    }
}

main().catch(console.error);
