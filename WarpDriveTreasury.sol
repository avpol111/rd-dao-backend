// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// Used to call a function to mint an impact token upon a donation.
interface IDonorSFT {
    function mintToken(address to, uint256 _amount) external;
}

// A secure vault receiving, holding and releasing funds.
contract WarpDriveTreasury is ReentrancyGuard {

    IDonorSFT donorSFT;
	
	struct Milestone {
	    uint256 amountToRelease;
        bool isCompleted;
        bool peerReviewApproved;
        uint256 targetTimeline;
    }
	
	enum State { Funding, Active, Success, Failed }

	Milestone[] public milestones; // milestones upon reaching which funds are released.
	uint256[] public immutable targetTimelineOffsets; // in how many days a milestone must be reached.
	State public state = State.Funding; // state of the DAO.
	address payable public immutable recipient; // recipient of the funds.
	address immutable peerReviewCouncilAddress; // another contract of the DAO.
	address immutable donorSFTAddress; // another contract of the DAO.
	address immutable governanceExecutorAddress; // another contract of the DAO.
	uint256 public constant target = 1000000 * 10**6; // fundraising goal (in USDT).
	uint256 public immutable fundraisingDeadline;
	uint256 public raisedAmount = 0;
	uint256 immutable peerReviewingDuration; // in days.
	mapping(address => uint256) public contributions; // contributors and contributions.
	
	constructor(
	    uint256[] memory _amountsToRelease, // upon each milestone.
		uint256[] memory _targetTimelineOffsets,
		address _recipient,
		address _peerReviewCouncilAddress,
		address _donorSFTAddress,
		address _governanceExecutorAddress,
		uint256 _fundraisingDuration, // in weeks.
		uint256 _peerReviewingDuration
	) {
		if (_amountsToRelease.length != _targetTimelineOffsets.length) {
            revert MismatchedInputArrays();
        }
		
		if (_amountsToRelease.length == 0) {
            revert EmptyMilestones();
        }
		
		for (uint256 i = 0; i < _amountsToRelease.length; i++) {
            if (_amountsToRelease[i] = 0) {
			    revert ZeroAmountToRelease(i);
			}
        }
		
		if (_targetTimelineOffsets.length == 0) {
            revert EmptyTargetTimelineOffsets();
        }
		
		for (uint256 i = 0; i < _targetTimelineOffsets.length; i++) {
            if (_targetTimelineOffsets[i] = 0) {
			    revert ZeroTargetTimelineOffset(i);
			}
        }
		
		for (uint256 i = 0; i < _amountsToRelease.length; i++) {
            milestones.push(Milestone({
                amountToRelease: _amountsToRelease[i]
            }));
			
			targetTimelineOffsets.push(_targetTimelineOffsets[i]);
        }
		
		if (_recipient == address(0)) {
		    revert InvalidRecipientAddress();
		}
		
		recipient = _recipient;
		
		if (_peerReviewCouncilAddress == address(0)) {
		    revert InvalidPeerReviewCouncilAddress();
		}
		
		peerReviewCouncilAddress = _peerReviewCouncilAddress;
		
		if (_donorSFTAddress == address(0)) {
		    revert InvalidDonorSFTAddress();
		}
		
		donorSFTAddress = _donorSFTAddress;
		
		if (_governanceExecutorAddress == address(0)) {
		    revert InvalidGovernanceExecutorAddress();
		}
		
		governanceExecutorAddress = _governanceExecutorAddress;
		
		if (_fundraisingDuration <= 0) {
		    revert InvalidFundraisingDuration();
		}
		
		fundraisingDeadline = block.timestamp + _fundraisingDuration weeks;
		
		if (_peerReviewingDuration <= 0) {
		    revert InvalidPeerReviewingDuration();
		}
		
		peerReviewingDuration = _peerReviewingDuration;
		
		donorSFT = IDonorSFT(donorSFTAddress);
	}
	
	error MismatchedInputArrays();
    error EmptyMilestones();
	error ZeroAmountToRelease(uint256 index);
	error EmptyTargetTimelineOffsets();
	error ZeroTargetTimelineOffset(uint256 index); 
	error InvalidRecipientAddress();
	error InvalidPeerReviewCouncilAddress();
	error InvalidDonorSFTAddress();
	error InvalidGovernanceExecutorAddress();
	error InvalidFundraisingDuration();
	error InvalidPeerReviewingDuration();
	error InvalidState(State expected, State current);
	error FundingPeriodExpired(uint256 deadline, uint256 currentTimestamp);
    error FundingOngoing(uint256 deadline, uint256 currentTimestamp);
	error StateStillActive();
	error OnlyPeerReviewContract();
	error InvalidMilestoneId(uint256 numberOfMilestones);
	error ReleaseTransferFailed;
	error NoFundsToRefund();
    error RefundTransferFailed();
	error MilestoneAlreadyCompleted();
	error MilestoneNotCompletedOrAlreadyApproved();
	error MilestoneAlreadyApproved();
	
	// a function can be called only if the DAO is in a certain state.
	modifier requireState(State _expectedState) {
        if (state != _expectedState) {
            revert InvalidState(_expectedState, state);
        }			
        _;
    }
	
	// a function can be called only by PeerReviewCouncil contract.
	modifier onlyPeerReview() {
        if (msg.sender != peerReviewCouncilAddress) {
            revert OnlyPeerReviewContract();
        }
        _;
    }

    event Contribution(address indexed _contributor, uint256 _amount, uint256 _time);
	event MilestoneFundsReleased(uint256 indexed _milestoneId, uint256 _amount);
	event Refund(address indexed _contributor, uint256 _amount);
	
	// handles receiving donations and triggers minting impact tokens.
	function receiveDonation() external payable {
	    if (block.timestamp > fundraisingDeadline) {
		    revert FundingPeriodExpired(fundraisingDeadline, block.timestamp);
		}
		contributions[msg.sender] += msg.value;
		raisedAmount += msg.value;
		emit Contribution(msg.sender, msg.value, block.timestamp);
		
		donorSFT.mintToken(msg.sender, msg.value);
	}
	
	// switches the DAO state after the fundraising deadline to Active or Failed.
	function updateFundingState() external requireState(State.Funding) {
	    if (raisedAmount >= target) {
			for (uint256 i = 0; i < targetTimelineOffsets.length; i++) {
			    milestones[i].targetTimeline = block.timestamp + targetTimelineOffsets[i] days;
			}
		    state = State.Active;
		} else if (block.timestamp >= fundraisingDeadline) {
            state = State.Failed;
	    } else {
		    revert FundingOngoing(fundraisingDeadline, block.timestamp);
		}
	}
	
	// switches the DAO state to Success if all milestones are completed & approved or Failed otherwise.
	function updateActiveState() external requireState(State.Active) {
	    if (milestones[milestones.length - 1].peerReviewApproved == true) {
		    state = State.Success;
			return;
		}
	        
		for (uint256 i = 0; i < milestones.length; i++) {
		    if (block.timestamp >= milestones[i].targetTimeline && milestones[i].isCompleted == false) {
			    state = State.Failed;
				return;
			}
			
			if (block.timestamp >= milestones[i].targetTimeline + peerReviewingDuration days && milestones[i].peerReviewApproved == false) {
			    state = State.Failed;
				return;
	        }	
		}
		revert StateStillActive();
    }			
	// releases funds upon reaching a milestone; called upon milestone approval by the peer-reviewers.
	function releaseMilestoneFunds(uint256 _milestoneId) external nonReentrant requireState(State.Active) onlyPeerReview {
	    if (_milestoneId < 0 || _milestoneId >= milestones.length) {
		    revert InvalidMilestoneId(milestones.length);
		}
	    (bool success, ) = recipient.call{value: milestones[_milestoneId].amountToRelease}("");
        if (success) {
		    emit MilestoneFundsReleased(_milestoneId, milestones[_milestoneId].amountToRelease);
		} else {
            revert ReleaseTransferFailed();
		}
	}
	
	// handles refunds if the DAO mission fails (funds not raised or milestones not reached).
	function claimRefund() external nonReentrant requireState(State.Failed) {
	    uint256 amount = contributions[msg.sender];
        if (amount == 0) {
            revert NoFundsToRefund();
        }

        contributions[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (success) {
		    emit Refund(msg.sender, amount);
		} else {
            revert RefundTransferFailed();
        }
    }
	// checks if the DAO state is Active; called in a modifier in PeerReviewCouncil contract.
	function isStateActive() external view returns (bool) {
        return (state == State.Active);
    }
	
	// called in PeerReviewCouncil contract when a milestone is submitted.
	function setMilestoneCompleted(uint256 _milestoneId) external onlyPeerReview {
		Milestone storage milestoneToUpdate = milestones[_milestoneId];
		if (milestoneToUpdate.isCompleted) {
		    revert MilestoneAlreadyCompleted();
		}
		milestoneToUpdate.isCompleted = true;	    
    }
    
	// checks (from PeerReviewCouncil contract) if a milestone can be approved: is it completed? isn't it already approved?
    function checkMilestoneBeforeReview(uint256 _milestoneId) external view {
	    if (!milestones[_milestoneId].isCompleted || milestones[_milestoneId].peerReviewApproved) {
		    revert MilestoneNotCompletedOrAlreadyApproved();
		}
	}
	
	// called in PeerReviewCouncil contract when a milestone is approved.
	function setMilestoneApproved(uint256 _milestoneId) external onlyPeerReview {
	    Milestone storage milestoneToUpdate = milestones[_milestoneId];
		if (milestoneToUpdate.peerReviewApproved) {
		    revert MilestoneAlreadyApproved();
		}
		milestoneToUpdate.peerReviewApproved = true;
	}
	
	// called in WarpDriveGovernance contract to check if a user has voting rights.
	function isContributor() external view returns (bool) {
	    return (contributions[msg.sender] > 0);
	}
}