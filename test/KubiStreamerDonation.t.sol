// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/KubiStreamerDonation.sol";
import "../contracts/interfaces/IERC20.sol";

// ───────────────────────────────────────────────
// Dummy token for testing
// ───────────────────────────────────────────────
contract MockERC20 is IERC20 {
    string public name = "MockToken";
    string public symbol = "MOCK";
    uint8 public override decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(uint256 supply) {
        _mint(msg.sender, supply);
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "ALLOWANCE");
        allowance[from][msg.sender] = allowed - value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }
}

// ───────────────────────────────────────────────
// Mock Uniswap router (no real swap)
// ───────────────────────────────────────────────
contract MockFactory {
    mapping(address => mapping(address => address)) pairs;
    function getPair(address a, address b) external view returns (address) {
        return pairs[a][b];
    }
    function setPair(address a, address b, address pair) external {
        pairs[a][b] = pair;
        pairs[b][a] = pair;
    }
}

contract MockRouter is IUniswapV2Router02 {
    address public immutable override WETH;
    MockFactory public immutable f;
    constructor(address _weth, address _factory) {
        WETH = _weth;
        f = MockFactory(_factory);
    }
    function factory() external view override returns (address) {
        return address(f);
    }

    function swapExactTokensForTokens(
        uint amountIn, uint, address[] calldata path, address to, uint
    ) external override returns (uint[] memory amounts) {
        IERC20(path[path.length - 1]).transfer(to, amountIn);
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountIn;
    }

    function swapExactETHForTokens(
        uint, address[] calldata, address to, uint
    ) external payable override returns (uint[] memory amounts) {
        amounts = new uint[](2);
        amounts[1] = msg.value;
        (bool ok, ) = payable(to).call{value: msg.value}("");
        require(ok, "ETH_SEND_FAIL");
    }
}

// ───────────────────────────────────────────────
// Test contract
// ───────────────────────────────────────────────
contract KubiStreamerDonationTest is Test {
    KubiStreamerDonation donation;
    MockERC20 tokenA; // ERC20 token
    MockERC20 tokenB; // primary token
    MockERC20 tokenC; // not allowed token
    MockRouter router;
    MockFactory factory;
    address superAdmin = address(0xAAA);
    address feeRecipient = address(0xFEE);
    address streamer = address(0xBEEF);
    address donor = address(0xCAFE);
    address weth = makeAddr("WETH");

    function setUp() public {
        // deploy factory & router
        factory = new MockFactory();
        router = new MockRouter(weth, address(factory));

        // deploy tokens
        tokenA = new MockERC20(1_000_000 ether);
        tokenB = new MockERC20(1_000_000 ether);
        tokenC = new MockERC20(1_000_000 ether);

        // fund router with tokenB for simulated swap
        tokenB.transfer(address(router), 1_000_000 ether);
        
        // deploy donation contract
        donation = new KubiStreamerDonation(
            address(router),
            superAdmin,
            250,
            feeRecipient
        );

        // pair tokens for swap test
        factory.setPair(address(tokenA), address(tokenB), address(0x1));
        factory.setPair(address(tokenA), weth, address(0x1));
        factory.setPair(weth, address(tokenA), address(0x4));
        factory.setPair(weth, address(tokenB), address(0x2));
        factory.setPair(address(tokenC), address(tokenA), address(0x3)); // ETH -> tokenB

        // fund donor
        tokenA.transfer(donor, 10_000 ether);
        tokenC.transfer(donor, 10_000 ether);
        vm.deal(donor, 100 ether);

        // global whitelist
        vm.prank(superAdmin);
        donation.setGlobalWhitelist(address(tokenA), true);
        donation.setGlobalWhitelist(address(tokenB), true);
        donation.setGlobalWhitelist(address(tokenC), true);
        donation.setGlobalWhitelist(address(0), true); // ETH
    }

    // ───────────────────────────────────────────────
    // TEST 1: ERC20 direct transfer
    // ───────────────────────────────────────────────
    function testDonateERC20_Direct() public {
        // streamer whitelist tokenA
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenA), true);
        donation.setStreamerWhitelist(streamer, address(tokenC), true);
        donation.setPrimaryToken(streamer, address(tokenA));
        vm.stopPrank();

        // donor approve and donate
        vm.startPrank(donor);
        tokenA.approve(address(donation), 100 ether);
        donation.donate(address(tokenA), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        // check streamer received (97.5 ether, fee 2.5)
        assertEq(tokenA.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(feeRecipient), 2.5 ether);
    }

    // ───────────────────────────────────────────────
    // TEST 2: ERC20 auto swap
    // ───────────────────────────────────────────────
    function testDonateERC20_AutoSwap() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenB), true);
        donation.setPrimaryToken(streamer, address(tokenB));
        vm.stopPrank();

        // donor approve and donate tokenA
        vm.startPrank(donor);
        tokenA.approve(address(donation), 100 ether);
        donation.donate(address(tokenA), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        // check streamer got tokenB
        assertEq(tokenB.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(feeRecipient), 2.5 ether);
    }

    // ───────────────────────────────────────────────
    // TEST 3: ETH direct
    // ───────────────────────────────────────────────
    function testDonateETH_Direct() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(0), true);
        vm.stopPrank();

        uint256 balanceBefore = streamer.balance;
        vm.prank(donor);
        donation.donate{value: 1 ether}(address(0), 0, streamer, 0, block.timestamp + 10);

        assertEq(streamer.balance - balanceBefore, 0.975 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
    }

    // ───────────────────────────────────────────────
    // TEST 4: ETH auto swap
    // ───────────────────────────────────────────────
    function testDonateETH_AutoSwap() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenB), true);
        donation.setPrimaryToken(streamer, address(tokenB));
        vm.stopPrank();

        uint256 before = streamer.balance;
        vm.prank(donor);
        donation.donate{value: 1 ether}(address(0), 0, streamer, 0, block.timestamp + 10);

        // verify auto swap simulated
        assertEq(streamer.balance, before + 0.975 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
    }
}