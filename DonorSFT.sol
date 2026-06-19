// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// A mint giving semi-fungible impact tokens to contributors of the DAO.
contract DonorSFT is ERC1155 {

    uint256 public constant BRONZE_TIER_DONOR_TOKEN = 0;
	uint256 public constant SILVER_TIER_DONOR_TOKEN = 1;
	uint256 public constant GOLD_TIER_DONOR_TOKEN = 2;
	address warpDriveTreasuryAddress; // the address of the treasury contract.
	
	constructor (
	    address _warpDriveTreasuryAddress
	) {
	    if (_warpDriveTreasuryAddress == address(0)) {
		    revert InvalidWarpDriveTreasuryAddress();
		}
		
		warpDriveTreasuryAddress = _warpDriveTreasuryAddress;
	}	
	
	error InvalidWarpDriveTreasuryAddress();
	error OnlyWarpDriveTreasury();
	
	// only WarpDriveTreasury contract can call this function.
	modifier onlyWarpDriveTreasury() {
	    if (msg.sender != warpDriveTreasuryAddress) {
            revert OnlyWarpDriveTreasury();
        }
        _;
    }
	
	// called in WarpDriveTreasury contract every time someone makes a donation.
	function mintToken(address to, uint256 _amount) external onlyWarpDriveTreasury {
	    uint256 id;
		if (_amount <= 5000) {
		    id = 0;
		} else if (_amount > 5000 && _amount <= 50000) {
		    id = 1;
		} else {
		    id = 2;
		}
		
		_mint(to, id, 1, "");
	}

}