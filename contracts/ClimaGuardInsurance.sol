// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/automation/AutomationCompatible.sol";

contract ClimaGuardInsurance is AutomationCompatibleInterface {
    address public insurer;
    AggregatorV3Interface public rainfallOracle;

    enum PolicyState { Active, Triggered, PaidOut }

    struct Policy {
        address payable user;
        uint256 premium;
        uint256 payout;
        uint256 threshold;
        uint256 startTime;
        uint256 duration;
        PolicyState state;
    }

    Policy[] public policies;

    constructor(address _oracle) {
        insurer = msg.sender;
        rainfallOracle = AggregatorV3Interface(_oracle);
    }

    function purchasePolicy(uint256 _threshold, uint256 _duration) external payable {
        require(msg.value > 0, "Premium required");

        policies.push(Policy({
            user: payable(msg.sender),
            premium: msg.value,
            payout: msg.value * 2,
            threshold: _threshold,
            startTime: block.timestamp,
            duration: _duration,
            state: PolicyState.Active
        }));
    }

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        for (uint i = 0; i < policies.length; i++) {
            Policy memory p = policies[i];
            if (p.state == PolicyState.Active && block.timestamp >= p.startTime + p.duration) {
                upkeepNeeded = true;
                performData = abi.encode(i);
                return (upkeepNeeded, performData);
            }
        }
        return (false, bytes(""));
    }

    function performUpkeep(bytes calldata performData) external override {
        uint index = abi.decode(performData, (uint));
        Policy storage p = policies[index];
        require(p.state == PolicyState.Active, "Policy not active");
        require(block.timestamp >= p.startTime + p.duration, "Not matured");

        (, int rainfall,,,) = rainfallOracle.latestRoundData();

        if (uint(rainfall) < p.threshold) {
            p.user.transfer(p.payout);
            p.state = PolicyState.PaidOut;
        } else {
            p.state = PolicyState.Triggered;
        }
    }

    function getPolicyCount() external view returns (uint) {
        return policies.length;
    }

    function getPolicy(uint index) external view returns (
        address, uint256, uint256, uint256, uint256, PolicyState
    ) {
        Policy memory p = policies[index];
        return (p.user, p.premium, p.payout, p.threshold, p.duration, p.state);
    }
}
