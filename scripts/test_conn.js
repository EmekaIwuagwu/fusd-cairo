const { RpcProvider, Account } = require('starknet');

async function main() {
    const rpc = 'https://api.cartridge.gg/x/starknet/sepolia';
    const provider = new RpcProvider({ nodeUrl: rpc });

    const accountAddress = '0x07bea8856fe0f34bca2ccce7589c4c4834e4288b3f09f916415d9d14d7882a83';
    const privateKey = '0x02e9953827beae10fdae64b9a0f11e99ab47fd904736f8dee242fe1663d24fe0';

    try {
        // v6+ Account constructor
        const account = new Account(provider, accountAddress, privateKey);
        // Wait, if that fails, try the object version
        console.log('Account Address:', account.address);
        const nonce = await account.getNonce();
        console.log('Nonce:', nonce);
    } catch (err) {
        console.log('Retrying with object constructor...');
        try {
            const account = new Account({ provider, address: accountAddress, signer: privateKey });
            console.log('Account Address:', account.address);
            const nonce = await account.getNonce();
            console.log('Nonce:', nonce);
        } catch (err2) {
            console.error('All attempts failed:', err2);
        }
    }
}

main();
