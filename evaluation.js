const EUR_IN_ETH = 1668
const winston = require('winston')

winston.configure({
    format: winston.format.simple(),
    level: 'warn',
    transports: [
        new winston.transports.Console({ json: false, colorize: true })
    ]
})

async function gasInEUR(gas) {
    const localGasPrice = web3.utils.toBN(await web3.eth.getGasPrice())
    // const medianGasPrice = web3.utils.toBN(web3.utils.toWei('35', 'gwei'))
    winston.info(`Local gas price: ${localGasPrice.toString()}`)
    // winston.info(`Median gas price: ${medianGasPrice.toString()}`)
    const localGasCostWei = gas.mul(localGasPrice)
    // const medianGasCostWei = openGas.mul(medianGasPrice)

    winston.info(`Local gas cost in wei: ${localGasCostWei.toString()}`)
    // winston.info(`Median gas cost in wei: ${medianGasCostWei.toString()}`)
    const localGasCostETH = web3.utils.fromWei(localGasCostWei, 'ether')
    // const medianGasCostETH = web3.utils.fromWei(medianGasCostWei, 'ether')
    winston.info(`Total gas cost in ether (local price): ${localGasCostETH} ETH`)
    // winston.info(`Total gas cost in ether (median price): ${medianGasCostETH} ETH`)
    const localGasCostEUR = localGasCostETH * EUR_IN_ETH
    // const medianGasCostEUR = medianGasCostETH * EUR_IN_ETH
    winston.info(`Total gas cost in EUR (local price): ${localGasCostEUR.toFixed(2)} €`)
    // winston.info(`Total gas cost in EUR (median price): ${medianGasCostEUR.toFixed(2)} €`)

    return localGasCostEUR
}

async function gasCost(n) {

    // warden number n
    winston.info(`n = ${n}`)

    //load the sign function
    const { signAutoIncrement, signState, signVirtualState } = require('../src/brick')

    const f = Math.floor((n - 1) / 3)
    winston.info(`f = ${f}`)
    const t = Math.min(2 * f + 1, n)
    winston.info(`t = ${t}`)

    winston.info('Retrieving accounts')
    const accounts = await web3.eth.getAccounts()
    const Brick = artifacts.require('Brick')

    const alice = accounts[0]
    const ingrid = accounts[1]
    const bob = accounts[2]
    const FEE = 20
    const watchtowers = []

    const alicePrivate = '0xcf163df783185ed9862902d89aaaee849004f5f79eb2b05f509046fcc27f48fb'
    const ingridPrivate = '0xf42e9d405dda9c048aeee66b5bd25b94c927004cb2fb2a8da74f3bd379b6bac4'
    const bobPrivate = '0x028b61df5284b3cee491b018e86c833b5ecdb48576f4a0e4c03e247fe1ec4c9e'

    for (let i = 0; i < n; ++i) {
        watchtowers.push(accounts[i + 3])
    }

    winston.info('Constructing brick')
    let brick = await Brick.new()


    // winston.info('Getting receipt')
    const receipt = await web3.eth.getTransactionReceipt(brick.transactionHash)
    winston.info('Calculating gas for construction')
    const deployGas = web3.utils.toBN(receipt.gasUsed)
    winston.warn(`Gas for deployment: ${deployGas.toString()}`)
    const deployGasEUR = await gasInEUR(deployGas)

    let tx = await brick.aliceFund(ingrid, watchtowers, { value: FEE / 2 + 5 })
    const aliceFundGas = web3.utils.toBN(tx.receipt.gasUsed)
    winston.warn(`Gas for Alice fund: ${aliceFundGas.toString()}`)

    tx = await brick.fundingrid({ from: ingrid, value: FEE / 2 + 12 })
    const ingridFundGas = web3.utils.toBN(tx.receipt.gasUsed)
    winston.warn(`Gas for Ingrid fund: ${ingridFundGas.toString()}`)

    let watchtowersGas = web3.utils.toBN(0)
    for (let idx = 0; idx < n; ++idx) {
        winston.info(`Watchtower ${idx} funding`)
        tx = await brick.fundWatchtower(idx, { from: watchtowers[idx], value: 50 })
        watchtowersGas = watchtowersGas.add(web3.utils.toBN(tx.receipt.gasUsed))
        winston.info(`Gas for ${idx}th watchtower ${tx.receipt.gasUsed.toString()}`)
    }
    winston.warn(`Gas for watchtowers fund: ${watchtowersGas.toNumber()}`)
    tx = await brick.open()
    const openCallGas = web3.utils.toBN(tx.receipt.gasUsed)
    winston.warn(`Gas for open call: ${openCallGas.toNumber()}`)
    const openGas = aliceFundGas.add(ingridFundGas).add(watchtowersGas).add(openCallGas)
    winston.warn(`Total open gas: ${openGas.toString()}`)


    //evaluate the gas fee for optimistic close
    tx = await brick.optimisticAliceClose(5, { from: alice })
    const aliceCloseGas = web3.utils.toBN(tx.receipt.gasUsed)
    tx = await brick.optimisticIngridClose({ from: ingrid })
    const ingridCloseGas = web3.utils.toBN(tx.receipt.gasUsed)
    const optimisticCloseGas = aliceCloseGas.add(ingridCloseGas)
    winston.warn(`Gas used for optimistic close: ${optimisticCloseGas}`)

    const openGasEUR = await gasInEUR(openGas)
    winston.info(`Total open gas cost (EUR): ${openGasEUR}`)

    const optimisticCloseGasEUR = await gasInEUR(optimisticCloseGas)

    //evaluate the gas fee for pessimistic payment channel close
    brick = await Brick.new()
    await brick.aliceFund(ingrid, watchtowers, { value: FEE / 2 + 5 })
    await brick.fundingrid({ from: ingrid, value: FEE / 2 + 12 })
    for (let idx = 0; idx < n; ++idx) {
        await brick.fundWatchtower(idx, { from: watchtowers[idx], value: 50 })
    }
    await brick.open()

    let aliceSig = signAutoIncrement(brick.address, 3, alicePrivate),
        ingridSig = signAutoIncrement(brick.address, 3, ingridPrivate)

    let watchtowerClaimsGas = web3.utils.toBN(0)
    for (let i = 0; i < t; ++i) {
        winston.info(`Watchtower ${i} claiming state`)
        tx = await brick.watchtowerClaimState({
            autoIncrement: 3,
            aliceSig,
            ingridSig
        }, i, { from: watchtowers[i] })
        watchtowerClaimsGas = watchtowerClaimsGas.add(web3.utils.toBN(tx.receipt.gasUsed))
        winston.warn(`Gas used by watchtower claim ${i}: ${web3.utils.toBN(tx.receipt.gasUsed)}`)
    }
    winston.warn(`Gas used by watchtower claims in pessimistic close: ${watchtowerClaimsGas}`)

    const state3 = {
        aliceValue: 10,
        channelValue: 17,
        autoIncrement: 3
    }

    // aliceSig = signAutoIncrement(brick.address, 3, alicePrivate)
    tx = await brick.pessimisticClose(state3, aliceSig, [], { from: ingrid })
    const closeGas = web3.utils.toBN(tx.receipt.gasUsed)
    winston.warn(`Gas used for final pessimistic close() call: ${closeGas}`)
    const pessimisticCloseGas = watchtowerClaimsGas.add(closeGas)
    const pessimisticCloseGasEUR = await gasInEUR(pessimisticCloseGas)
    winston.info(`Total pessimistic close gas (EUR): ${pessimisticCloseGasEUR} €`)







    //evaluate gas fee for pessimistic closing for virtual channel closing
    brick = await Brick.new()

    winston.info('Constructing another brick')
    let brick2 = await Brick.new()

    const address1 = brick.address

    const address2 = brick2.address

    await brick.aliceFund(ingrid, watchtowers, {from: alice, value: FEE / 2 + 5 })
    await brick.fundingrid({ from: ingrid, value: FEE / 2 + 12 })
    for (let idx = 0; idx < n; ++idx) {
        await brick.fundWatchtower(idx, { from: watchtowers[idx], value: 50 })
    }
    await brick.open()

    await brick2.aliceFund(ingrid, watchtowers, {from: bob, value: FEE / 2 + 5 })
    await brick2.fundingrid({ from: ingrid, value: FEE / 2 + 12 })
    for (let idx = 0; idx < n; ++idx) {
        await brick2.fundWatchtower(idx, { from: watchtowers[idx], value: 50 })
    }
    await brick2.open()

    const vopenstate = {
        aliceValue: 2,
        vchannelValue: 3,
        autoIncrement: 1
    };
    
    const vstate = {
        aliceValue: 1,
        vchannelValue: 3,
        autoIncrement: 4
    };

    let alicevopenSig = signVirtualState(address1, vopenstate, alicePrivate),
        bobvopenSig = signVirtualState(address1, vopenstate, bobPrivate),
        ingridvopneSig = signVirtualState(address1, vopenstate, ingridPrivate)

    const txranc = {
        RTx:{Alice : alice,
        Bob : bob,
        Ingrid: ingrid,
        AliceContract: address1,
        BobContract: address2,
        openstate: vopenstate,
        },
        aliceSig : alicevopenSig,
        ingridSig : ingridvopneSig,
        bobSig : bobvopenSig
    }
    tx = await brick.VirtualchannelRegister(txranc, { from: ingrid })
    const registerGas = web3.utils.toBN(tx.receipt.gasUsed)

    
    let alicevSig = signVirtualState(address1, vstate, alicePrivate),
        bobvSig = signVirtualState(address1, vstate, bobPrivate);
    
    let watchtowerVirtualClaimsGas = web3.utils.toBN(0);
    
    for (let i = 0; i < t; ++i) {
        winston.info(`Watchtower ${i} claiming state`);
        tx = await brick.VirtualwatchtowerClaimState({
            state: {
                aliceValue: 1,
                vchannelValue: 3,
                autoIncrement: 4
            },
            aliceSig: alicevSig,
            bobSig: bobvSig,
        }, i, { from: watchtowers[i] });
    
        watchtowerVirtualClaimsGas = watchtowerVirtualClaimsGas.add(web3.utils.toBN(tx.receipt.gasUsed));
        winston.warn(`Gas used by watchtower claim ${i} for virtual channel: ${web3.utils.toBN(tx.receipt.gasUsed)}`);
    }
    
    winston.warn(`Total gas used for all watchtower claims: ${watchtowerVirtualClaimsGas.toString()}`);
    winston.warn(`Gas used by watchtower claims in pessimistic virtual channel close: ${watchtowerVirtualClaimsGas}`);
    tx = await brick.pessimisticVirtualChannelClose([], { from: ingrid });
    // let adressA1 = await brick._alicecontract();
    // console.log(`Alice address 1: ${adressA1.toString()}`);
    // console.log(`Alice address 2: ${address1}`);
    const closevGas = web3.utils.toBN(tx.receipt.gasUsed);
    tx = await brick. FinalClose({ from: alice });
    const finalvGas = web3.utils.toBN(tx.receipt.gasUsed);
    const finalvallGas = closevGas.add(finalvGas);
    winston.warn(`Gas used for final pessimistic virtual channel close() call: ${finalvallGas}`);
    const pessimisticvCloseGas = watchtowerVirtualClaimsGas.add(closevGas);
    const pessimisticCloseGasAll = pessimisticvCloseGas.add(registerGas);
    const pessimisticvCloseGasEUR = await gasInEUR(pessimisticCloseGasAll);
    winston.info(`Total pessimistic close gas (EUR): ${pessimisticvCloseGasEUR} €`);


    return {
        deploy: deployGasEUR.toFixed(2),
        open: openGasEUR.toFixed(2),
        optimisticClose: optimisticCloseGasEUR.toFixed(2),
        pessimisticVClose: pessimisticvCloseGasEUR.toFixed(2),
        pessimisticClose: pessimisticCloseGasEUR.toFixed(2)
    }
}

module.exports = async (callback) => {
    try {
        const Promise = require('bluebird')
        const fs = Promise.promisifyAll(require('fs'))
        const graphs = {
            deploy: [],
            open: [],
            optimisticClose: [],
            pessimisticVClose: [],
            pessimisticClose: []
        }

        for (let n = 10; n <= 25; n = n+3) {
            const cost = await gasCost(n)
            graphs.deploy.push(cost.deploy)
            graphs.open.push(cost.open)
            graphs.optimisticClose.push(cost.optimisticClose)
            graphs.pessimisticVClose.push(cost.pessimisticVClose)
            graphs.pessimisticClose.push(cost.pessimisticClose)
        }
        await fs.writeFileAsync('/Users/yuhengwang/Code/Thunderdome/data.json', JSON.stringify(graphs))

        callback()
    }
    catch (err) {
        callback(err)
    }
}
