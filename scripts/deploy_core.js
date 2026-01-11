const { Account, RpcProvider, json, uint256, hash } = require('starknet');
const fs = require('fs');
const path = require('path');

async function main() {
    const rpcUrl = 'https://api.cartridge.gg/x/starknet/sepolia';
    const provider = new RpcProvider({ nodeUrl: rpcUrl });

    const accountAddress = '0x07bea8856fe0f34bca2ccce7589c4c4834e4288b3f09f916415d9d14d7882a83';
    const privateKey = '0x02e9953827beae10fdae64b9a0f11e99ab47fd904736f8dee242fe1663d24fe0';

    // v6+ Account constructor requires options object
    const account = new Account({
        provider,
        address: accountAddress,
        signer: privateKey
    });

    console.log('Account connected:', account.address);

    const artifactPath = path.join(__dirname, '..', 'target', 'dev');

    const contracts = [
        'Treasury',
        'OracleAdapter',
        'FUSDToken',
        'Staking',
        'BondToken',
        'BondAuction',
        'LiquidityManager',
        'MonetaryPolicy'
    ];

    const classHashes = {};

    for (const name of contracts) {
        console.log(`Checking/Declaring ${name}...`);
        const sierraFile = fs.readFileSync(path.join(artifactPath, `fusd_${name}.contract_class.json`));
        const casmFile = fs.readFileSync(path.join(artifactPath, `fusd_${name}.compiled_contract_class.json`));

        const sierra = json.parse(sierraFile.toString());
        const casm = json.parse(casmFile.toString());

        const computedHash = hash.computeSierraContractClassHash(sierra);
        classHashes[name] = computedHash;

        try {
            await provider.getClassByHash(computedHash);
            console.log(`${name} already declared. Hash:`, computedHash);
        } catch (err) {
            console.log(`${name} not declared. Declaring...`);
            try {
                const nonce = await account.getNonce('latest');
                const declareResponse = await account.declare({ contract: sierra, casm: casm }, { nonce });
                console.log(`${name} declared. Tx:`, declareResponse.transaction_hash);
                await provider.waitForTransaction(declareResponse.transaction_hash);
            } catch (decErr) {
                console.error(`Failed to declare ${name}:`, decErr);
                return;
            }
        }
    }

    console.log('Class Hashes:', classHashes);

    // DEPLOYMENT SEQUENCE
    const deployedAddresses = {};

    async function deploy(name, calldata) {
        console.log(`Deploying ${name}...`);
        const nonce = await account.getNonce('latest');
        const res = await account.deployContract({
            classHash: classHashes[name],
            constructorCalldata: calldata
        }, { nonce });
        console.log(`${name} deployed at: ${res.contract_address}`);
        await provider.waitForTransaction(res.transaction_hash);
        deployedAddresses[name] = res.contract_address;
        return res.contract_address;
    }

    // 1. Treasury
    await deploy('Treasury', [accountAddress]);

    // 2. OracleAdapter
    await deploy('OracleAdapter', ['3', '0x1', '0x2', '0x3', accountAddress]);

    // 3. FUSD Token
    const fusdSupply = uint256.bnToUint256('1000000000000000000');
    await deploy('FUSDToken', [
        fusdSupply.low, fusdSupply.high,
        accountAddress, // recipient
        accountAddress  // admin
    ]);

    // 4. Staking
    await deploy('Staking', [deployedAddresses['FUSDToken'], accountAddress]);

    // 5. BondToken
    await deploy('BondToken', [accountAddress]);

    // 6. BondAuction
    await deploy('BondAuction', [
        deployedAddresses['FUSDToken'],
        deployedAddresses['BondToken'],
        accountAddress
    ]);

    // 7. LiquidityManager
    await deploy('LiquidityManager', [deployedAddresses['FUSDToken'], accountAddress]);

    // 8. MonetaryPolicy
    await deploy('MonetaryPolicy', [
        deployedAddresses['FUSDToken'],
        deployedAddresses['OracleAdapter'],
        deployedAddresses['Treasury'],
        deployedAddresses['LiquidityManager'],
        deployedAddresses['Staking'],
        deployedAddresses['BondToken'],
        deployedAddresses['BondAuction'],
        accountAddress
    ]);

    console.log('All contracts deployed! Setting up permissions...');

    const roles = {
        ADMIN: '0x41444d494e', // 'ADMIN'
        MINTER: '0x4d494e544552', // 'MINTER'
        BURNER: '0x4255524e4552'  // 'BURNER'
    };

    const grantRole = async (target, role, accountAddr) => {
        console.log(`Granting ${role} role on ${target} to ${accountAddr}...`);
        const nonce = await account.getNonce('latest');
        const tx = await account.execute({
            contractAddress: target,
            entrypoint: 'grant_role',
            calldata: [role, accountAddr]
        }, { nonce });
        await provider.waitForTransaction(tx.transaction_hash);
        console.log(`Granted ${role} role. Tx: ${tx.transaction_hash}`);
    };

    await grantRole(deployedAddresses['FUSDToken'], roles.MINTER, deployedAddresses['MonetaryPolicy']);
    await grantRole(deployedAddresses['FUSDToken'], roles.BURNER, deployedAddresses['BondAuction']);
    await grantRole(deployedAddresses['BondToken'], roles.MINTER, deployedAddresses['BondAuction']);
    await grantRole(deployedAddresses['Staking'], roles.ADMIN, deployedAddresses['MonetaryPolicy']);

    console.log('Deployment and setup complete! 🚀');
    console.log('Summary:', JSON.stringify(deployedAddresses, null, 2));

    fs.writeFileSync('deployment_summary.json', JSON.stringify(deployedAddresses, null, 2));
}

main().catch(console.error);
