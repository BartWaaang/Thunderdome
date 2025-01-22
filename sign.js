const channelStateType = {
    'aliceValue': 'uint256',
    'channelValue': 'uint256',
    'autoIncrement': 'uint16'
}

const virtualchannelStateType = {
    'aliceValue': 'uint256',
    'VchannelValue': 'uint256',
    'autoIncrement': 'uint16'
}


const stateType = ['address', { ChannelState: channelStateType }]
const vstateType = ['address', { ChannelState: virtualchannelStateType}]
const autoIncrementType = ['address', 'uint16']
const valueType = ['address','uint256']
const Web3 = require('web3')
const web3 = new Web3(new Web3.providers.HttpProvider('http://localhost:8545'))

function hexToBytes(hex) {
    let bytes = ''

    for (let c = 0; c < hex.length; c += 2) {
        bytes += String.fromCharCode(parseInt(hex.substr(c, 2), 16))
    }
    return bytes
}

function offchainSign(msg, privateKey) {
    const msgHex = Buffer.from(msg, 'latin1').toString('hex')
    const msgHashHex = web3.utils.keccak256('0x' + msgHex)
    const sig = web3.eth.accounts.sign(msgHashHex, privateKey)

    let { v, r, s } = sig
    v = parseInt(v, 16)

    return { v, r, s }
}

function signRawMessage(type, rawValue, privateKey) {
    const encodedMsg = hexToBytes(web3.eth.abi.encodeParameters(
        type, rawValue
    ).slice(2))

    return offchainSign(encodedMsg, privateKey)
}

function signState(address, state, privateKey) {
    return signRawMessage(stateType, [address, state], privateKey)
}

function signAutoIncrement(address, autoIncrement, privateKey) {
    return signRawMessage(
        autoIncrementType,
        [address, autoIncrement],
        privateKey
    )
}

function offchainvirtualSign(msg, privateKey) {
    const msgHex = Buffer.from(msg, 'latin1').toString('hex')
    const sig = web3.eth.accounts.sign(msgHex, privateKey)

    let { v, r, s } = sig
    v = parseInt(v, 16)

    return { v, r, s }
}

function virtualsignRawMessage(type, rawValue, privateKey) {
    const encodedMsg = hexToBytes(web3.eth.abi.encodeParameters(
        type, rawValue
    ).slice(2))

    return offchainvirtualSign(encodedMsg, privateKey)
}

function signvirtualState(address, state, privateKey) {
    return virtualsignRawMessage(stateType, [address, state], privateKey)
}

function signvirtualAutoIncrement(address, autoIncrement, privateKey) {
    return virtualsignRawMessage(
        autoIncrementType,
        [address, autoIncrement],
        privateKey
    )
}

function signvirtualvalue(address, value, privateKey) {
    return virtualsignRawMessage(
        valueType,
        [address, value],
        privateKey
    )
}



module.exports = { hexToBytes, offchainSign, signState, signAutoIncrement, offchainvirtualSign
,  virtualsignRawMessage, signvirtualState, signvirtualAutoIncrement, signvirtualvalue}