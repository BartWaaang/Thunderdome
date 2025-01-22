/*
SPDX-License-Identifier: MIT
*/

pragma solidity >=0.5.16;
pragma experimental ABIEncoderV2;

library BrickBase {
    function divceil(uint a, uint m) 
    internal pure returns (uint) { 
        return (a + m - 1) / m;
    }
}


struct ChannelState {//payment channel state between Alice and Ingrid
        uint256 aliceValue;
        uint256 channelValue;
        uint16 autoIncrement;//sequence number
    }

    struct VirtualChannelState {//virtual channel state between Alice and Bob
        uint256 aliceValue;
        uint256 vchannelValue;
        uint16 autoIncrement;
    }

    struct ECSignature {//the ecs signature
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct Announcement {//payment channel state broacast to wardens
        uint16 autoIncrement;// Brick only requires to publish sequence number
        ECSignature aliceSig;// signature on the hashed sequece number
        ECSignature ingridSig;//Pyament channel state is signed by Alice and Ingrid
    }

    struct VirtualAnnouncement {//virtual channel state broacast to wardens
        VirtualChannelState state;// Thunderdome requires to publish the original state
        ECSignature aliceSig;//
        ECSignature bobSig;//Thunderdome state needs to be signed by the other party
    }

    struct RegisterTransaction {//Registration transaction
        address Alice;
        address Bob;
        address Ingrid;//Three main parties' addresses
        address AliceContract;//Assume Alice is the default leader contract
        address BobContract;//Contract's address
        VirtualChannelState openstate;
    }

    struct RegisterAnnounce{//The registration transaction announcement that is published onchain
        RegisterTransaction RTx;
        ECSignature aliceSig;
        ECSignature ingridSig;
        ECSignature bobSig;
    }

    struct FraudProof {//proof-of-fraud
        Announcement statePoint;//announcement
        ECSignature watchtowerSig;//warden signature
        uint8 watchtowerIdx;//warden identity
    }

    struct VirtualFraudProof {//proof-of-fraud
        VirtualAnnouncement statePoint;//announcement
        ECSignature watchtowerSig;//warden signature
        uint8 watchtowerIdx;//warden identity
    }


interface CounterContract {
    function ReceiveRequest(uint256, uint16) external returns (uint256, uint16);
}

contract Brick {//We use Brick channel as the underlying TPC
    enum BrickPhase {// payment channel phases: CrossChecked is for Thunderdome
        Deployed, AliceFunded, IngridFunded,
        Open, CrossChecked, Closed
    }

    mapping (uint16 => bool) announcementAutoIncrementSigned; //payment channel mapping
    mapping (uint16 => bool) virtualannouncementStateSigned; //Virtual channel mapping
    mapping (uint16 => bool) virtualregisterSigned; //Virtual channel register mapping


    uint256 public _initialAliceValue;//Alice initial money for payment channel
    uint256 public _initialIngridValue;//Ingrid initial money for payment channel
    uint256 public _virtualAliceValue;//Alice initial money for virtual channel
    uint256 public _virtualIngridValue;//Ingrid initial money for virtual channel
    uint256 public _initialChannelValue;//Initial channel value of payment channel
    uint256 public _ChannelValue;//Payment channel balance
    uint256 public _VChannelValue;//Virtual channel balance
    uint256 public _VChannelClosedValue;//The sum of already closed virtual channel money
    uint256 public _crossaliceValue;
    uint16 public _crossautoIncrement;
    uint256 public _crossaliceValueStore;
    uint16 public _crossautoIncrementStore;
    uint8 public _n;//n
    uint8 public _t;//t
    uint256 constant public FEE = 20 wei; // must be even
    uint8 public _f;//f
    address payable public _alice;// alice address
    address payable public _ingrid;//ingrid address
    address public _bob;//Virtual channel counterparty address, can be extended to multi-party by using list here
    address payable[] public _watchtowers;//warden address
    address public _alicecontract = address(this);//Own address
    address public _bobcontract;//Counterparty address
    BrickPhase public _phase;// payment channel phase
    bool[] public _watchtowerFunded;// warden fund or not
    uint256 public _collateral;//warden collateral
    bool public _ingridFunded;//ingrid fund
    bool public _leader;//leader contract
    bool watchtowerclaimed;
    VirtualAnnouncement public _FinalState;//final state for unilateral closing

    uint16[] _watchtowerLastAutoIncrement;
    uint16[] _watchtowerLastAutoIncrementVirtual;
    uint256[] _watchtowerLastValueVirtual;
    Announcement _bestAnnouncementPayment;
    VirtualAnnouncement _bestAnnouncementVirtual;
    // bool[] _watchtowerClaimedClose;
    bool[] _watchtowerClaimedVirtualClose;
    bool[] _watchtowerClaimedPaymentClose;
    uint8 _numWatchtowerPaymentClaims;
    uint8 _numWatchtowerVirtualClaims;
    uint16 _maxWatchtowerAutoIncrementPaymentClaim;
    uint16 _maxWatchtowerAutoIncrementVirtualClaim;
    bool _aliceWantsClose;
    uint256 _aliceClaimedClosingValue;
    uint8 _numHonestClosingWatchtowers;

    modifier atPhase(BrickPhase phase) {
        require(_phase == phase, 'Invalid phase');
        _;
    }

    modifier aliceOnly() {
        require(msg.sender == _alice, 'Only Alice is allowed to call that');
        _;
    }

    modifier ingridOnly() {
        require(msg.sender == _ingrid, 'Only Ingrid is allowed to call that');
        _;
    }

    modifier openOnly() {
        require(_phase == BrickPhase.Open, 'Channel is not open');
        _;
    }

    function aliceFund(address payable ingrid, address payable[] memory watchtowers)
    public payable atPhase(BrickPhase.Deployed) {

        _n = uint8(watchtowers.length);//load parameters
        _f = (_n - 1) / 3;
        _t = 2*_f + 1;

        _alice = payable(msg.sender);//Alice first fund
        _initialAliceValue = msg.value - FEE / 2;
        _ingrid = ingrid;
        _watchtowers = watchtowers;
        for (uint8 i = 0; i < _n; ++i) {
            _watchtowerFunded.push(false);//initialize warden states
            _watchtowerClaimedVirtualClose.push(false);
            _watchtowerClaimedPaymentClose.push(false);
            _watchtowerLastAutoIncrement.push(0);
            _watchtowerLastAutoIncrementVirtual.push(0);
            _watchtowerLastValueVirtual.push(0);
        }
        _phase = BrickPhase.AliceFunded;
    }

    function fundingrid() external payable atPhase(BrickPhase.AliceFunded) {
        //Ingrid fund
        require(msg.value >= FEE / 2, 'ingrid must pay at least the fee');
        _initialIngridValue = msg.value - FEE / 2;
        _ingridFunded = true;
        
        //calculate each warden collateral
        if (_f > 0) {
            _collateral = BrickBase.divceil(_initialAliceValue + _initialIngridValue, _f);
        }

        //change state
        _phase = BrickPhase.IngridFunded;

        //calculate the initial channel value
        _initialChannelValue = _initialAliceValue + _initialIngridValue;
        _ChannelValue=_initialChannelValue;
    }

    function fundWatchtower(uint8 idx)
    external payable atPhase(BrickPhase.IngridFunded) {// watchtower fund the channel
        require(msg.value >= _collateral, 'Watchtower must pay at least the collateral');
        _watchtowerFunded[idx] = true;
    }
    

    function open() external atPhase(BrickPhase.IngridFunded) {//open the payment channel
        
        for (uint8 idx = 0; idx < _n; ++idx) {
            require(_watchtowerFunded[idx], 'All watchtowers must fund the channel before opening it');
        }

        //change the state
        _phase = BrickPhase.Open;
        _bestAnnouncementVirtual.state.aliceValue =0 ;
        _bestAnnouncementVirtual.state.autoIncrement = 0;
        watchtowerclaimed = false;
    }

    function optimisticAliceClose(uint256 closingAliceValue)
    public openOnly aliceOnly {//optimistic closing
        
        //no extra money is giving
        require(closingAliceValue <=
                _initialAliceValue + _initialIngridValue, 'Channel cannot close at a higher value than it began at');
        
        // Ensure Alice doesn't later change her mind about the value
        // in a malicious attempt to frontrun ingrid's optimisticingridClose()
        require(!_aliceWantsClose, 'Alice can only decide to close with one state');
        _aliceWantsClose = true;
        _aliceClaimedClosingValue = closingAliceValue;
    }

    function optimisticIngridClose()
    public openOnly ingridOnly {//optimisitic closing finished by Ingrid
        require(_aliceWantsClose, 'ingrid cannot close on his own volition');

        //change the state and tranfer the money
        _phase = BrickPhase.Closed;
        _alice.transfer(_aliceClaimedClosingValue + FEE / 2);
        _ingrid.transfer(_initialChannelValue - _aliceClaimedClosingValue + FEE / 2);

        //wardens get back collateral
        for (uint256 idx = 0; idx < _n; ++idx) {
            _watchtowers[idx].transfer(_collateral);
        }
    }


    function watchtowerClaimState(Announcement memory announcement, uint256 idx)
    public openOnly {//watchtower publish payment channel information to the blockchain
        
        //Verify the announcement first
        require(validAnnouncement(announcement), 'Announcement does not have valid signatures by Alice and ingrid');
        require(msg.sender == _watchtowers[idx], 'This is not the watchtower claimed');
        require(!_watchtowerClaimedPaymentClose[idx], 'Each watchtower can only submit one pessimistic state');
        require(_numWatchtowerPaymentClaims < _t, 'Watchtower race is complete');

        //record the annoucement published by wardens
        _watchtowerLastAutoIncrement[idx] = announcement.autoIncrement;
        _watchtowerClaimedPaymentClose[idx] = true;
        ++_numWatchtowerPaymentClaims;

        if (announcement.autoIncrement > _maxWatchtowerAutoIncrementPaymentClaim) {
            _maxWatchtowerAutoIncrementPaymentClaim = announcement.autoIncrement;
            _bestAnnouncementPayment = announcement;
        }
    }

    function VirtualchannelRegister (RegisterAnnounce memory txr)
    public openOnly{

        require(msg.sender == _alice || msg.sender == _ingrid, 'Only Alice or Ingrid can pessimistically close the channel');
        
        _bob = txr.RTx.Bob;
        _bobcontract = txr.RTx.BobContract;

        if (_alice == payable(txr.RTx.Alice)){
            _leader = true;
        }


        require(validRegisterAnnouncement(txr), 'Register transaction does not have enough signatures');

        _bobcontract = txr.RTx.BobContract;
        _VChannelValue = txr.RTx.openstate.vchannelValue;

    }


    function VirtualwatchtowerClaimState(VirtualAnnouncement memory announcement, uint256 idx)
    public openOnly {

        // verify the announcement first
        require(validVirtualAnnouncement(announcement), 'Announcement does not have valid signatures by Alice and Bob');
        require(msg.sender == _watchtowers[idx], 'This is not the watchtower claimed');
        require(!_watchtowerClaimedVirtualClose[idx], 'Each watchtower can only submit one pessimistic state');
        require(_numWatchtowerVirtualClaims < _t, 'Watchtower race is complete');

        // _watchtowerLastAutoIncrement[idx] = announcement.autoIncrement;
        _watchtowerLastAutoIncrementVirtual[idx] = announcement.state.autoIncrement;
        _watchtowerLastValueVirtual[idx] = announcement.state.aliceValue;

        _watchtowerClaimedVirtualClose[idx] = true;
        ++_numWatchtowerVirtualClaims;

        if (announcement.state.autoIncrement > _maxWatchtowerAutoIncrementVirtualClaim) {
            _maxWatchtowerAutoIncrementVirtualClaim = announcement.state.autoIncrement;
            _bestAnnouncementVirtual = announcement;
        }
        watchtowerclaimed = true;
    }

    
//     function pessimisticVirtualChannelClose(RegisterAnnounce memory txr, VirtualFraudProof[] memory proofs)
//     public openOnly {
        
//         if (_phase == BrickPhase.CrossChecked) {
//             _FinalState = _bestAnnouncementVirtual;
//             return;
//         }

//         require(_numWatchtowerVirtualClaims >= _t, 'At least 2f+1 watchtower claims are needed for pessimistic close');
        

//         //verify the fraud proof
//         for (uint256 i = 0; i < proofs.length; ++i) {
//             uint256 idx = proofs[i].watchtowerIdx;
//             require(validVirtualFraudProof(proofs[i]), 'Invalid fraud proof');
//             // Ensure there's at most one fraud proof per watchtower
//             require(_watchtowerFunded[idx], 'Duplicate fraud proof');
//             _watchtowerFunded[idx] = false;
//         }


//        if (proofs.length <= _f) {


//             if (_phase != BrickPhase.RequestSent) {
//             CounterContract(_bobcontract).ReceiveRequest(
//                 _alicecontract,
//                 _bestAnnouncementVirtual
//             );
//             _phase = BrickPhase.RequestSent;
//             return;
//         }
//         }

//         else {
//             counterparty(msg.sender).transfer(_VChannelValue);
//         }
//         payable(msg.sender).transfer((_collateral * _VChannelValue/_initialChannelValue) * proofs.length);
//         _ChannelValue = _ChannelValue -  _VChannelValue;
//     }


//     function ReceiveRequest(address sender, VirtualAnnouncement memory state) external {
//     if (_phase == BrickPhase.CrossChecked) {
//         return; // Already cross-checked, no further processing needed
//     }

//     // Update _bestAnnouncementVirtual if necessary
//     if (
//         _bestAnnouncementVirtual.state.autoIncrement == 0 || // Empty _bestAnnouncementVirtual
//         state.state.autoIncrement > _bestAnnouncementVirtual.state.autoIncrement || // Higher autoIncrement
//         (state.state.autoIncrement == _bestAnnouncementVirtual.state.autoIncrement && sender == _alicecontract) // Same autoIncrement, prefer sender
//     ) {
//         _bestAnnouncementVirtual = state;
      
//     }

//     // // Update _FinalState and set the phase to CrossChecked
//     _FinalState = _bestAnnouncementVirtual;
//     _phase = BrickPhase.CrossChecked;

//     // Notify the sender with the updated _bestAnnouncementVirtual
//     CounterContract(sender).ReceiveRequest(_alicecontract, state);
// }

    function pessimisticVirtualChannelClose(VirtualFraudProof[] memory proofs) public openOnly {
    require(_numWatchtowerVirtualClaims >= _t, 'At least 2f+1 watchtower claims are needed for pessimistic close');

    for (uint256 i = 0; i < proofs.length; ++i) {
        uint256 idx = proofs[i].watchtowerIdx;
        require(validVirtualFraudProof(proofs[i]), 'Invalid fraud proof');
        require(_watchtowerFunded[idx], 'Duplicate fraud proof');
        _watchtowerFunded[idx] = false;
    }

    if (proofs.length <= _f) {
        if (_phase != BrickPhase.CrossChecked) {
            require(_bobcontract != address(0), "Invalid _bobcontract address");

            // require(_bestAnnouncementVirtual.state.aliceValue >= 0,"Invalid aliceValue: must be non-negative");
            // require(_bestAnnouncementVirtual.state.autoIncrement >= 1,"Invalid autoIncrement: must be at least 1");
            
            //  (_crossaliceValue, _crossautoIncrement) = (0,0);

            (_crossaliceValue, _crossautoIncrement) = CounterContract(_bobcontract).ReceiveRequest(
                _bestAnnouncementVirtual.state.aliceValue, 
                _bestAnnouncementVirtual.state.autoIncrement
            );

            if (
                _crossautoIncrement == 0 || 
                _crossautoIncrement < _bestAnnouncementVirtual.state.autoIncrement ||
                (_crossautoIncrement == _bestAnnouncementVirtual.state.autoIncrement && !_leader)
            ) {
                _phase = BrickPhase.CrossChecked;
            } else {
                _bestAnnouncementVirtual.state.aliceValue = _crossaliceValue;
                _bestAnnouncementVirtual.state.autoIncrement = _crossautoIncrement;
                _phase = BrickPhase.CrossChecked;
            }
        } else {
            _bestAnnouncementVirtual.state.aliceValue = _crossaliceValueStore;
            _bestAnnouncementVirtual.state.autoIncrement = _crossautoIncrementStore;
        }
    } else {
        require(_VChannelValue <= _ChannelValue, "Insufficient channel value");
        counterparty(msg.sender).transfer(_VChannelValue);
    }

    uint256 payout = (_collateral * _VChannelValue) / _initialChannelValue;
    require(_initialChannelValue > 0, "Invalid initial channel value");
    require(payout <= address(this).balance, "Insufficient balance for payout");
    payable(msg.sender).transfer(payout * proofs.length);

    require(_VChannelValue <= _ChannelValue, "Invalid channel value update");
    _ChannelValue = _ChannelValue - _VChannelValue;
}


    function ReceiveRequest(uint256 aliceValue, uint16 autoIncrement) external returns (uint256, uint16) {
    
    _crossaliceValueStore = aliceValue;
    _crossautoIncrementStore = autoIncrement;

    if(!watchtowerclaimed){
        return (0,0);
    }

    else {
        
    return  (_bestAnnouncementVirtual.state.aliceValue, _bestAnnouncementVirtual.state.autoIncrement);}

}


    function FinalClose() public {
        _FinalState = _bestAnnouncementVirtual;
        require(msg.sender == _alice || msg.sender == _ingrid, 'Only Alice or Ingrid can pessimistically close the channel');
        require(_FinalState.state.aliceValue > 0, "Invalid FinalState");
        require(_phase == BrickPhase.CrossChecked, "Not crosschecked");
        

        // Send the coins to Alice
        _alice.transfer(_FinalState.state.aliceValue);
        _ingrid.transfer(_FinalState.state.vchannelValue - _FinalState.state.aliceValue);
    }

    function watchtowerRedeemCollateral(uint256 idx)
    public atPhase(BrickPhase.Closed) {
        // require(msg.sender == _watchtowers[idx], 'This is not the watchtower claimed');
        require(_watchtowerFunded[idx], 'Malicious watchtower tried to redeem collateral; or double collateral redeem');

        _watchtowerFunded[idx] = false;
        _watchtowers[idx].transfer(_collateral + FEE / _numHonestClosingWatchtowers);
    }


    function pessimisticClose(ChannelState memory closingState, ECSignature memory counterpartySig, FraudProof[] memory proofs)
    public openOnly {
        require(closingState.channelValue + _VChannelClosedValue == _initialChannelValue, 'Virtual channel is not closed');
        require(msg.sender == _alice || msg.sender == _ingrid, 'Only Alice or ingrid can pessimistically close the channel');
        require(_bestAnnouncementPayment.autoIncrement == closingState.autoIncrement, 'Channel must close at latest state');
        require(closingState.aliceValue <=
                _initialAliceValue + _initialIngridValue, 'Channel must conserve monetary value');
        require(_numWatchtowerPaymentClaims >= _t, 'At least 2f+1 watchtower claims are needed for pessimistic close');
        bytes32 plaintext = keccak256(abi.encode(address(this), closingState));
        // require(checkPrefixedSig(counterparty(msg.sender), plaintext, counterpartySig), 'Counterparty must have signed closing state');
        bool check = checkPrefixedSig(counterparty(msg.sender), plaintext, counterpartySig);


        for (uint256 i = 0; i < proofs.length; ++i) {
            uint256 idx = proofs[i].watchtowerIdx;
            require(validFraudProof(proofs[i]), 'Invalid fraud proof');
            // Ensure there's at most one fraud proof per watchtower
            require(_watchtowerFunded[idx], 'Duplicate fraud proof');
            _watchtowerFunded[idx] = false;
        }

        _numHonestClosingWatchtowers = _n - uint8(proofs.length);
        _phase = BrickPhase.Closed;

        if (proofs.length <= _f) {
            _alice.transfer(closingState.aliceValue);
            _ingrid.transfer(closingState.channelValue - closingState.aliceValue);
        }
        else {
            counterparty(msg.sender).transfer(closingState.channelValue);
        }
        payable(msg.sender).transfer(_collateral * (closingState.channelValue/_initialChannelValue) * proofs.length);
        for (uint8 idx = 0; idx < _n; ++idx) {
            watchtowerRedeemCollateral(idx);
        }
    }

    // function checkSig(address pk, bytes32 plaintext, ECSignature memory sig)
    // public pure returns(bool) {
    //     return ecrecover(plaintext, sig.v, sig.r, sig.s) == pk;
    // }

    // function checkPrefixedSig(address pk, bytes32 message, ECSignature memory sig)
    // public pure returns(bool) {
    //     bytes32 prefixedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message));

    //     return ecrecover(prefixedHash, sig.v, sig.r, sig.s) == pk;
    // }

    function checkPrefixedSig(address pk, bytes32 message, ECSignature memory sig)
    public pure returns(bool) {
    bytes32 prefixedHash = keccak256(
        abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
    );
    return ecrecover(prefixedHash, sig.v, sig.r, sig.s) == pk;
}


    // function validAnnouncement(Announcement memory announcement)
    // public returns(bool) {//verify the validity of wardens' messages

    //     //Already verify to be valid
    //     if (announcementAutoIncrementSigned[announcement.autoIncrement]) {
    //         return true;
    //     }
    //     bytes32 message = keccak256(abi.encode(address(this), announcement.autoIncrement));

    //     if (checkPrefixedSig(_alice, message, announcement.aliceSig) &&
    //         checkPrefixedSig(_ingrid, message, announcement.ingridSig)) {
    //         announcementAutoIncrementSigned[announcement.autoIncrement] = true;
    //         return true;
    //     }
    //     return false;
    // }

    function validAnnouncement(Announcement memory announcement)
    public returns(bool) {
    if (announcementAutoIncrementSigned[announcement.autoIncrement]) {
        return true;
    }

    bytes32 message = keccak256(abi.encode(address(this), announcement.autoIncrement));

    if (checkPrefixedSig(_alice, message, announcement.aliceSig) &&
        checkPrefixedSig(_ingrid, message, announcement.ingridSig)) {
        announcementAutoIncrementSigned[announcement.autoIncrement] = true;
        return true;
    }
    return false;
}

    function validRegisterAnnouncement(RegisterAnnounce memory txr)
    public returns(bool) {

        bytes32 message = keccak256(abi.encode(address(this), txr.RTx.openstate));

        if (checkPrefixedSig(_alice, message, txr.aliceSig) && 
            checkPrefixedSig(_ingrid, message, txr.ingridSig) &&
            checkPrefixedSig(_bob, message, txr.bobSig)){               
                return true;
            } 
            return false;
    }

    function validVirtualAnnouncement(VirtualAnnouncement memory announcement)
    public returns(bool) {
        if (virtualannouncementStateSigned[announcement.state.autoIncrement]) {
            return true;
        }

        bytes32 message = keccak256(abi.encode(address(this), announcement.state));

        if (checkPrefixedSig(_alice, message, announcement.aliceSig) &&
            checkPrefixedSig(_bob, message, announcement.bobSig)) {
            virtualannouncementStateSigned[announcement.state.autoIncrement] = true;
            return true;
        }
        return false;
    }

    function counterparty(address party)
    internal view returns (address payable) {
        if (party == _alice) {
            return _ingrid;
        }
        return _alice;
    }

    function staleClaim(FraudProof memory proof)
    internal view returns (bool) {
        uint256 watchtowerIdx = proof.watchtowerIdx;

        return proof.statePoint.autoIncrement >
               _watchtowerLastAutoIncrement[watchtowerIdx];
    }

    function staleVirtualClaim(VirtualFraudProof memory proof)
    internal view returns (bool) {
        uint256 watchtowerIdx = proof.watchtowerIdx;

        return (proof.statePoint.state.autoIncrement >
               _watchtowerLastAutoIncrement[watchtowerIdx]) || ((proof.statePoint.state.autoIncrement ==
               _watchtowerLastAutoIncrement[watchtowerIdx]) && proof.statePoint.state.aliceValue !=  _watchtowerLastValueVirtual[watchtowerIdx]);
    }

    function validFraudProof(FraudProof memory proof)
    public view returns (bool) {
        return checkPrefixedSig(
            _watchtowers[proof.watchtowerIdx],
            keccak256(abi.encode(address(this), proof.statePoint.autoIncrement)),
            proof.watchtowerSig
        ) && staleClaim(proof);
    }

    function validVirtualFraudProof(VirtualFraudProof memory proof)
    public view returns (bool) {
        return checkPrefixedSig(
            _watchtowers[proof.watchtowerIdx],
            keccak256(abi.encode(address(this), proof.statePoint.state.autoIncrement)),
            proof.watchtowerSig
        ) && checkPrefixedSig(
            _watchtowers[proof.watchtowerIdx],
            keccak256(abi.encode(address(this), proof.statePoint.state.aliceValue)),
            proof.watchtowerSig
        ) &&  staleVirtualClaim(proof);
    }
}
