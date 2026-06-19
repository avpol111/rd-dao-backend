// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Used to call functions working with the DAO state and milestones[] array in the treasury contract.
interface IWarpDriveTreasury {
    function isStateActive() external view returns (bool);
	function setMilestoneCompleted(uint256 _milestoneId) external;
	function checkMilestoneBeforeReview(uint256 _milestoneId) external view;
	function setMilestoneApproved(uint256 _milestoneId) external;
	function releaseMilestoneFunds(uint256 _milestoneId) external;
}

// A contract containing logic related to milestone submission and peer-reviewing.
contract PeerReviewCouncil {

    IWarpDriveTreasury warpDriveTreasury;
	
    struct Reviewer {
        address reviewerAddress;
		string expertMetadataURI;
		bool isActive;
	}
	
	struct PeerReview {
        uint256 startTime;
		uint8 yesVotes;
        mapping(address => uint256) votingTime; 
    }
	
	PeerReview[] public peerReviews; // peer-reviews of milestones.
	Reviewer[3] public reviewers;
	bytes32[] public proofHashes; // hashes of URIs of milestone reaching proofs.
	address payable immutable recipient; // funds recipient; submits milestone reaching proofs.
	address immutable warpDriveTreasuryAddress; // another contract of the DAO.
	address immutable governanceExecutorAddress; // another contract of the DAO.
	uint256 immutable numberOfMilestones;
	uint256 public immutable peerReviewingDuration; // in days.
	
	constructor(
	    address[3] memory _peerReviewersAddresses,
		string[3] memory _expertMetadataURIs, // links to the peer-reviewers' details.
		address _recipient,
		address _warpDriveTreasuryAddress,
		address _governanceExecutorAddress,
		uint256 _numberOfMilestones,
		uint256 _peerReviewingDuration
	) {
	    for (uint256 i = 0; i < 3; i++) {
            if (_peerReviewersAddresses[i] == address(0)) {
                revert ZeroAddressNotAllowed(i);
            }
        }
		
		for (uint256 i = 0; i < 3; i++) {
		    if (bytes(_expertMetadataURIs[i]).length == 0) {
			    revert EmptyMetadataURI(i);
			}
		}
		
        for (uint256 i = 0; i < 3; i++) {
            reviewers.push(Reviewer({
                reviewerAddress: _peerReviewersAddresses[i],
                expertMetadataURI: _expertMetadataURIs[i],
                isActive: true
            }));
        }
		
		for (uint256 i = 0; i < _numberOfMilestones; i++) {
		    PeerReview storage newReview = peerReviews.push();
			newReview.votingTime[_peerReviewersAddresses[i]] = 0;
		}

        if (_recipient == address(0)) {
		    revert InvalidRecipientAddress();
		}
		
		recipient = _recipient;
		
		if (_warpDriveTreasuryAddress == address(0)) {
		    revert InvalidWarpDriveTreasuryAddress();
		}
		
		warpDriveTreasuryAddress = _warpDriveTreasuryAddress;

        if (_governanceExecutorAddress == address(0)) {
		    revert InvalidGovernanceExecutorAddress();
		}
		
		governanceExecutorAddress = _governanceExecutorAddress;

        if (_numberOfMilestones <= 0) {
            revert InvalidNumberOfMilestones();
        }

        numberOfMilestones = _numberOfMilestones;
		
		if (_peerReviewingDuration <= 0) {
		    revert InvalidPeerReviewingDuration();
		}
		
		peerReviewingDuration = _peerReviewingDuration;

        warpDriveTreasury = IWarpDriveTreasury(warpDriveTreasuryAddress);		
	}
	
	error ZeroAddressNotAllowed(uint256 index);
	error EmptyMetadataURI (uint256 index);
	error InvalidRecipientAddress();
	error InvalidWarpDriveTreasuryAddress();
	error InvalidGovernanceExecutorAddress();
	error InvalidNumberOfMilestones();
	erroe InvalidPeerReviewingDuration();
	error StateNotActive();
	error OnlyRecipient();
	error InvalidMilestoneId(uint256 numberOfMilestones);
	error PeerReviewPeriodExpired(uint256 deadline);
	error ReviewerAlreadyVoted();
	error InvalidMilestoneProof();
	error NotAuthorizedToReview();
	error OnlyGovernanceExecutor();
	error InvalidReviewerToFlagId();
	error RewieverAlreadyInactivated();
	error InvalidReviewerToRemoveId();
	error InvalidReviewerToAddAddress();
	error EmptyExpertMetadataURI();
	error AllReviewersActive();
	
	// a function can be called only if the DAO is in Active state.
	modifier onlyWhileActive() {
	    if (!warpDriveTreasury.isStateActive()) {
		    revert StateNotActive();
		}
		_;
	}
	
	// a function can be called only by the funds recipient.
	modifier onlyRecipient() {
	    if (msg.sender != recipient) {
            revert OnlyRecipient();
        }
        _;
    }
	
	// a function can be called only by one of the peer-reviewers.
	modifier onlyReviewers() {
	    _checkIfReviewer();
		_;
	}
	
	// a function can be called only by WarpDriveGovernance contract.
	modifier onlyGovernanceExecutor() {
	    if (msg.sender != governanceExecutorAddress) {
            revert OnlyGovernanceExecutor();
        }
        _;
    }
	
	event MilestoneProofSubmitted(uint256 indexed _milestoneId, string _proof);
	event VoteCast(address indexed _peerReviewer, bool _vote);
	event ProofInvalid();
	event ProofValid();
	event ReviewerFlagged(address indexed _flaggedReviewer);
	event ReviewerRotated(address indexed _removedReviewer, address indexed _newReviewer);
	
	// called by the funds recipient to submit a link to the proof of reaching a milestone.
	function submitMilestoneProof(uint256 _milestoneId, string calldata _proofToHash) external onlyWhileActive onlyRecipient {
	    if (_milestoneId < 0 || _milestoneId >= numberOfMilestones) {
		    revert InvalidMilestoneId(numberOfMilestones);
		}
		
		if (bytes(_proofToHash).length == 0) {
		    revert InvalidMilestoneProof();
		}
		
		bytes32 _proofHash = keccak256(abi.encodePacked(_proofToHash));
		proofHashes[_milestoneId] = _proofHash;
		
		warpDriveTreasury.setMilestoneCompleted(_milestoneId);
		PeerReview storage reviewToSetStartTime = peerReviews[_milestoneId];
		reviewToSetStartTime.startTime = block.timestamp;
		emit MilestoneProofSubmitted(_milestoneId, _proofToHash);
	}
	
	// called by a peer-reviewer to vote on a milestone submitted.
	function voteOnMilestone(uint256 _milestoneId, bool _approve) external onlyWhileActive onlyReviewers {
	    if (_milestoneId < 0 || _milestoneId >= numberOfMilestones) {
		    revert InvalidMilestoneId(numberOfMilestones);
		}
		
		warpDriveTreasury.checkMilestoneBeforeReview(_milestoneId);

		if (block.timestamp >= peerReviews[_milestoneId].startTime + peerReviewingDuration days) {
		    revert PeerReviewPeriodExpired(peerReviews[_milestoneId].startTime + peerReviewingDuration days);
		}
		
		PeerReview storage reviewToVote = peerReviews[_milestoneId]
		if (reviewToVote.votingTime[msg.sender] != 0) {
		    revert ReviewerAlreadyVoted();
		}
		if (_approve) {
		    reviewToVote.yesVotes += 1;
		}
		reviewToVote.votingTime[msg.sender] = block.timestamp;
		emit VoteCast(msg.sender, _approve);
		if (reviewToVote.yesVotes >= 2) {
		    warpDriveTreasury.setMilestoneApproved(_milestoneId);
			warpDriveTreasury.releaseMilestoneFunds(_milestoneId);
        }			
	}
	
	// called to check if a milestone proof link has been changed.
	function checkProofIntegrity(uint256 _milestoneId, string calldata _proofToCheck) external view onlyWhileActive {
	    if (_milestoneId < 0 || _milestoneId >= numberOfMilestones) {
		    revert InvalidMilestoneId(numberOfMilestones);
		}
		if (bytes(_proofToCheck).length == 0) {
		    revert InvalidMilestoneProof();
		}
		bytes32 _proofHash = keccak256(abi.encodePacked(_proofToCheck));
		if (proofHashes[_milestoneId] != _proofHash) {
		    emit ProofInvalid();
		} else {
		    emit ProofValid();
		}
	}
	
	// called to flag an inactive peer-reviewer.
	function flagReviewer(uint256 _reviewerId, uint256 _milestoneId) external onlyWhileActive {
	    if (_reviewerId < 0 || _reviewerId >= 3) {
		    revert InvalidReviewerToFlagId();
		}
	
		if (_milestoneId < 0 || _milestoneId >= numberOfMilestones) {
		    revert InvalidMilestoneId(numberOfMilestones);
		}
		
	    if (reviewers[reviewerId].isActive == false) {
		    revert RewieverAlreadyInactivated();
		}
		
		if (block.timestamp >= peerReviews[_milestoneId].startTime + peerReviewingDuration days && peerReviews[_milestoneId].votingTime[reviewers[reviewerId].reviewerAddress] == 0) {
		    reviewers[reviewerId].isActive = false;
		}
		emit ReviewerFlagged(reviewers[reviewerId].reviewerAddress);
	}
	
	// checks if at least 1 peer-reviewer is inactive to propose another one; called in a modifier in WarpDriveGovernance contract. 
	function isFlagged() external view returns (bool) {
	    for (uint256 i = 0; i < 3; i++) {
		    if (!reviewers[i].isActive) {
			    return true;
			}
		}
		return false;
	}
	
	// gets the id of the peer-reviewer who's being removed due to inactivity; called in WarpDriveGovernance contract.
	function getReviewerToRemoveId() external view returns (uint256) {
	    for (uint256 i = 0; i < 3; i++) {
		    if (!reviewers[i].isActive) {
			    return i;
			}
		}
	}
	
	// called in WarpDriveGovernance contract to substitute a new peer-reviewer for an inactive one.
	function rotateReviewer(uint256 _reviewerToRemoveId, address _reviewerToAddAddress, string calldata _reviewerToAddMetadataURI) external onlyWhileActive onlyGovernanceExecutor {
	    if (_reviewerToRemoveId < 0 || _reviewerToRemoveId >= 3) {
		    revert InvalidReviewerToRemoveId();
		}
		
		if (_reviewerToAddAddress == address(0)) {
		    revert InvalidReviewerToAddAddress();
		}
		
		if (bytes(_reviewerToAddMetadataURI).length == 0) {
		    revert EmptyExpertMetadataURI();
		}
		
		if (reviewers[_reviewerToRemoveId].isActive == true) {
		    revert AllReviewersActive();
		}
		
		address _reviewerToRemoveAddress = reviewers[_reviewerToRemoveId].reviewerAddress;
		
		delete reviewers[_reviewerToRemoveId];
		
		reviewers[_reviewerToRemoveId] = Reviewer({
            reviewerAddress: _reviewerToAddAddress,
            expertMetadataURI: _reviewerToAddMetadataURI,
            isActive: true
		});
		
		emit ReviewerRotated(_reviewerToRemoveAddress, _reviewerToAddAddress);
	}
	
	// a helper function called in onlyReviewers modifier.
	function _checkIfReviewer() internal view {
	    if (
		    msg.sender != reviewers[0].reviewerAddress ||
		    msg.sender != reviewers[1].reviewerAddress ||
			msg.sender != reviewers[2].reviewerAddress) {
			    revert NotAuthorizedToReview();
		}
	}
}