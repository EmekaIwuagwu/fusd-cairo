const { Account, RpcProvider, hash } = require('starknet');

async function main() {
    const rpcUrl = 'https://api.cartridge.gg/x/starknet/sepolia';
    const provider = new RpcProvider({ nodeUrl: rpcUrl });

    const accountAddress = '0x07bea8856fe0f34bca2ccce7589c4c4834e4288b3f09f916415d9d14d7882a83';
    const privateKey = '0x02e9953827beae10fdae64b9a0f11e99ab47fd904736f8dee242fe1663d24fe0';

    const account = new Account({ provider, address: accountAddress, signer: privateKey });

    const addresses = {
        FUSDToken: '0x3cad60c63e40c0d306e5b5ae19b697d1e808aa4e8e2bea14d17dd50aabb82dc',
        MonetaryPolicy: '0x401a15f31c83f49d8ac347e9d4c3e4404b0fc716a4e26e699e717e4f66cd7e0',
        BondAuction: '0x3b83fe2ad4bb0d49de91b7bd061518040aacb728570ae65cd1dcfea7368cef3',
        BondToken: '0x75c3c12ad0fc159ecffc3c27ec36c6de2cf1eb30aad9f81c4fe857155104675'
    };

    const roles = {
        MINTER: '0x4d494e544552', // 'MINTER'
        BURNER: '0x4255524e4552'  // 'BURNER'
    };

    console.log('Granting MINTER role on FUSD to MonetaryPolicy...');
    const nonce1 = await account.getNonce('latest');
    const tx1 = await account.execute({
        contractAddress: addresses.FUSDToken,
        entrypoint: 'grant_role',
        calldata: [roles.MINTER, addresses.MonetaryPolicy]
    }, { nonce: nonce1 });
    console.log('Tx1:', tx1.transaction_hash);
    await provider.waitForTransaction(tx1.transaction_hash);

    console.log('Granting BURNER role on FUSD to BondAuction...');
    const nonce2 = await account.getNonce('latest');
    const tx2 = await account.execute({
        contractAddress: addresses.FUSDToken,
        entrypoint: 'grant_role',
        calldata: [roles.BURNER, addresses.BondAuction]
    }, { nonce: nonce2 });
    console.log('Tx2:', tx2.transaction_hash);
    await provider.waitForTransaction(tx2.transaction_hash);

    console.log('Granting MINTER role on BondToken to BondAuction...');
    const nonce3 = await account.getNonce('latest');
    const tx3 = await account.execute({
        contractAddress: addresses.BondToken,
        entrypoint: 'grant_role',
        calldata: [roles.MINTER, addresses.BondAuction]
    }, { nonce: nonce3 });
    console.log('Tx3:', tx3.transaction_hash);
    await provider.waitForTransaction(tx3.transaction_hash);

    console.log('All permissions set! 🚀');
}

main().catch(console.error);
