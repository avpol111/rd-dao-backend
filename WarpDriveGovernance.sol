// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Used to call functions working with the DAO state and contributions[] array.
interface IWarpDriveTreasury {
    function isStateActive() external view returns (bool);
    function isContributor() external view returns (bool);
}

// Used to call functions working with peer-reviewers data.
interface IPeerReviewCouncil {
    function isFlagged() external view returns (bool);
	function getReviewerToRemoveId() external view returns (uint256);
    function rotateReviewer(uint256 _reviewerToRemoveId, address _reviewerToAddAddress, string calldata _reviewerToAddMetadataURI) external;
}

// A contract with the logic of nominating and electing peer-reviewers instead of inactive ones.
contract WarpDriveGovernance {
    IWarpDriveTreasury warpDriveTreasury;
	IPeerReviewCouncil peerReviewCouncil;
	
	address immutable warpDriveTreasuryAddress; // another contract of the DAO.
	address immutable peerReviewCouncilAddress; // another contract of the DAO.
	address public reviewerAddress; // address of the nominee proposed as a new peer-reviewer.
	string public expertMetadataURI; // link to the nominee's details.
	uint256 public endTime; // voting deadline.
	uint256 public immutable votingDuration; // in days.
	uint256 public votesFor;
	uint256 public votesAgainst;
	
	constructor (
	    address _warpDriveTreasuryAddress,
		address _peerReviewCouncilAddress,
		uint256 _votingDuration
	) {
	    if (_warpDriveTreasuryAddress == address(0)) {
		    revert InvalidWarpDriveTreasuryAddress();
		}
		
		warpDriveTreasuryAddress = _warpDriveTreasuryAddress;
		
		if (_peerReviewCouncilAddress == address(0)) {
		    revert InvalidPeerReviewCouncilAddress();
		}
		
		peerReviewCouncilAddress = _peerReviewCouncilAddress;
		
		if (_votingDuration <= 0) {
		    revert InvalidVotingDuration();
		}
		
		votingDuration = _votingDuration;
		
		warpDriveTreasury = IWarpDriveTreasury(warpDriveTreasuryAddress);
		peerReviewCouncil = IPeerReviewCouncil(peerReviewCouncilAddress);
	}
	
	error InvalidWarpDriveTreasuryAddress();
	error InvalidPeerReviewCouncilAddress();
	error InvalidVotingDuration();
	error StateNotActive();
	error NotContributor();
	error NotFlagged();
	error ActiveVoting();
	error NoVotingHeld();
	error VotingExpired(uint256 endTime);
	error InvalidReviewerAddress();
	error EmptyExpertMetadataURI();
	
	// a function can be called only if the DAO is in Active state.
	modifier onlyWhileActive() {
	    if (!warpDriveTreasury.isStateActive()) {
		    revert StateNotActive();
		}
		_;
	}
	
	// a function can be called only by a DAO contributor.
	modifier onlyContributor() {
	    if (!warpDriveTreasury.isContributor()) {
		    revert NotContributor();
		}
		_;
	}
	
	// a function can only be called if at least 1 peer-reviewer is inactive (to propose another one).
	modifier onlyFlagged() {
	    if (!peerReviewCouncil.isFlagged()) {
		    revert NotFlagged();
		}
		_;
	}
	
	// a function can be called only if no voting is being conducted.
	modifier onlyIfNoVotingActive() {
	    if (endTime != 0) {
		    revert ActiveVoting();
		}
		_;
	}
	
	// a function can be called only if a voting is being conducted.
	modifier onlyIfVotingHeld() {
	    if (endTime = 0) {
		    revert NoVotingHeld();
		}
		_;
	}
	
	// a function can be called only if an active voting isn't expired yet.
	modifier onlyIfNotExpired() {
	    if (block.timestamp >= endTime) {
		    revert VotingExpired(endTime);
		}
		_;
	}
	
	event ReviewerProposed(address indexed _reviewerAddress);
	event VoteCast(address indexed _voter, bool _vote);
	event VotingEnded(uint256 _votesFor, uint256 _votesAgainst);
	
	// called by a DAO contributor to propose a new peer-reviewer (to be voted on) instead of an inactive one.
	function proposeReviewer(address _reviewerAddress, string calldata _expertMetadataURI) external onlyWhileActive onlyContributor onlyFlagged onlyIfNoVotingActive {
        if (_reviewerAddress == address(0)) {
		    revert InvalidReviewerAddress();
		}
		
		if (bytes(_expertMetadataURI).length == 0) {
		    revert EmptyExpertMetadataURI();
		}
		
		reviewerAddress = _reviewerAddress;
		expertMetadataURI = _expertMetadataURI;
		endTime = block.timestamp + votingDuration days;
		
		emit ReviewerProposed(_reviewerAddress);
	}
    
	// called by a DAO contributor to vote on a nominee for peer-reviewer.
    function voteOnReviewer(bool _vote) external onlyWhileActive onlyContributor onlyIfVotingHeld onlyIfNotExpired {
	    if (_vote) {
		    votesFor += 1;
	    } else {
		    votesAgainst +=1;
		}
		emit VoteCast(msg.sender, _vote);
	}
	
	// called to close a voting once the deadline passes and to appoint the nominee if elected.
	function inactivateVoting() external onlyWhileActive onlyIfVotingHeld {
	    if (block.timestamp >= endTime) {
		    if (votesFor > votesAgainst) {
			    uint256 _reviewerToRemoveId = peerReviewCouncil.getReviewerToRemoveId();
			    peerReviewCouncil.rotateReviewer(_reviewerToRemoveId, reviewerAddress, expertMetadataURI);
			}
			
			emit VotingEnded(votesFor, votesAgainst);
			
			reviewerAddress = address(0);
			expertMetadataURI = "";
			endTime = 0;
			votesFor = 0;
			votesAgainst = 0;
		} else {
		   revert ActiveVoting();
		}
	}
}