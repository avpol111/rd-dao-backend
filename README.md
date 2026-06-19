# rd-dao-backend
The backend for a DAO that raises funds for an experimental physics project (a warp drive) and then releases these funds upon reaching research milestones.
The process looks like this: first, fundraising is conducted, with a deadline being fixed; after the deadline, if the funds are raised, the R&D team starts working, submitting the results of each stage of the work (milestones). A panel of three peer-reviewers votes on each milestone, and if the latter is approved, a portion of the funds is released, going to the R&D team.
The code is grouped into four contracts:
1) WarpDriveTreasury handles receiving donations, releasing funds, and refunding in case of a failure (if either the funds aren't raised or any milestone isn't submitted or approved);
2) PeerReviewCouncil contains logic related to milestone submission by the R&D team, peer-reviewing milestones by the panel of reviewers, and replacing a reviewer if he/she has become inactive;
3) DonorSFT is responsible for minting semi-fungible impact tokens for those who have contributed financially to the DAO;
4) WarpDriveGovernance handles situations, where voting must be held to replace an inactive peer-reviewer.
