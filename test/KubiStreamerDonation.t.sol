// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/KubiStreamerDonation.sol";
import "../contracts/interfaces/IERC20.sol";
import "../contracts/interfaces/IYieldWrapper.sol";

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
// Mock Uniswap router (no real pricing)
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
        uint256 amountIn,
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external override returns (uint256[] memory amounts) {
        require(IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn), "ROUTER_PULL_FAIL");
        require(IERC20(path[path.length - 1]).transfer(to, amountIn), "ROUTER_SEND_FAIL");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountIn;
    }

    function swapExactETHForTokens(
        uint256,
        address[] calldata path,
        address to,
        uint256
    ) external payable override returns (uint256[] memory amounts) {
        require(IERC20(path[path.length - 1]).transfer(to, msg.value), "ROUTER_SEND_FAIL");
        amounts = new uint256[](path.length);
        amounts[0] = msg.value;
        amounts[amounts.length - 1] = msg.value;
    }
}

// ───────────────────────────────────────────────
// Mock yield token implementing simple mint logic
// ───────────────────────────────────────────────
contract MockYieldToken is IERC20, IYieldWrapper {
    string public name = "MockYield";
    string public symbol = "MYIELD";
    uint8 public override decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    IERC20 public immutable underlyingToken;
    address public owner;
    address public depositor;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DepositorUpdated(address indexed newDepositor);

    constructor(IERC20 _underlying) {
        underlyingToken = _underlying;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    function underlying() external view override returns (address) {
        return address(underlyingToken);
    }

    function setDepositor(address _depositor) external onlyOwner {
        depositor = _depositor;
        emit DepositorUpdated(_depositor);
    }

    function depositYield(address user, uint256 amount) external override {
        require(msg.sender == depositor, "NOT_DEPOSITOR");
        require(amount > 0, "INVALID_AMOUNT");
        require(underlyingToken.transferFrom(msg.sender, address(this), amount), "TRANSFER_FAIL");
        balanceOf[user] += amount;
        totalSupply += amount;
        emit Transfer(address(0), user, amount);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "ALLOWANCE");
        allowance[from][msg.sender] = allowed - value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
}

// ───────────────────────────────────────────────
// Test contract
// ───────────────────────────────────────────────
contract KubiStreamerDonationTest is Test {
    KubiStreamerDonation donation;
    MockERC20 tokenA; // ERC20 token
    MockERC20 tokenB; // primary token / vault underlying
    MockERC20 tokenC; // extra token
    MockYieldToken yieldToken;
    MockRouter router;
    MockFactory factory;
    address superAdmin = address(0xAAA);
    address feeRecipient = address(0xFEE);
    address streamer = address(0xBEEF);
    address donor = address(0xCAFE);
    address weth = makeAddr("WETH");

    function setUp() public {
        factory = new MockFactory();
        router = new MockRouter(weth, address(factory));

        tokenA = new MockERC20(1_000_000 ether);
        tokenB = new MockERC20(1_000_000 ether);
        tokenC = new MockERC20(1_000_000 ether);
        yieldToken = new MockYieldToken(IERC20(address(tokenB)));

        tokenA.approve(address(router), type(uint256).max);
        require(tokenB.transfer(address(router), 1_000_000 ether), "FUND_ROUTER");

        donation = new KubiStreamerDonation(address(router), superAdmin, 250, feeRecipient);
        yieldToken.setDepositor(address(donation));

        factory.setPair(address(tokenA), address(tokenB), address(0x1));
        factory.setPair(address(tokenB), address(tokenA), address(0x1));
        factory.setPair(address(tokenA), weth, address(0x4));
        factory.setPair(weth, address(tokenA), address(0x4));
        factory.setPair(weth, address(tokenB), address(0x2));
        factory.setPair(address(tokenB), weth, address(0x2));
        factory.setPair(address(tokenC), address(tokenA), address(0x3));
        factory.setPair(address(tokenA), address(tokenC), address(0x3));

        require(tokenA.transfer(donor, 10_000 ether), "FUND_DONOR_A");
        require(tokenC.transfer(donor, 10_000 ether), "FUND_DONOR_C");
        vm.deal(donor, 100 ether);

        vm.startPrank(superAdmin);
        donation.setGlobalWhitelist(address(tokenA), true);
        donation.setGlobalWhitelist(address(tokenB), true);
        donation.setGlobalWhitelist(address(tokenC), true);
        donation.setGlobalWhitelist(address(0), true); // ETH
        vm.stopPrank();
    }

    function testDonateERC20_Direct() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenA), true);
        donation.setStreamerWhitelist(streamer, address(tokenC), true);
        donation.setPrimaryToken(streamer, address(tokenA));
        vm.stopPrank();

        vm.startPrank(donor);
        tokenA.approve(address(donation), 100 ether);
        donation.donate(donor, address(tokenA), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(feeRecipient), 2.5 ether);
    }

    function testDonateERC20_AutoSwap() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenB), true);
        donation.setPrimaryToken(streamer, address(tokenB));
        vm.stopPrank();

        vm.startPrank(donor);
        tokenA.approve(address(donation), 100 ether);
        donation.donate(donor, address(tokenA), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        assertEq(tokenB.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(feeRecipient), 2.5 ether);
    }

    function testDonateETH_Direct() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(0), true);
        vm.stopPrank();

        uint256 balanceBefore = streamer.balance;
        vm.prank(donor);
        donation.donate{value: 1 ether}(donor, address(0), 0, streamer, 0, block.timestamp + 10);

        assertEq(streamer.balance - balanceBefore, 0.975 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
    }

    function testDonateETH_AutoSwap() public {
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(tokenB), true);
        donation.setPrimaryToken(streamer, address(tokenB));
        vm.stopPrank();

        vm.prank(donor);
        donation.donate{value: 1 ether}(donor, address(0), 0, streamer, 0, block.timestamp + 10);

        assertEq(tokenB.balanceOf(streamer), 0.975 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
    }

    function testDonateERC20_Yield() public {
        vm.startPrank(superAdmin);
        donation.setYieldConfig(address(yieldToken), address(tokenB), address(0), true, 0);
        donation.setStreamerYieldContract(streamer, address(yieldToken));
        vm.stopPrank();

        vm.startPrank(donor);
        tokenA.approve(address(donation), 100 ether);
        donation.donate(donor, address(tokenA), 100 ether, streamer, 0, block.timestamp + 10);
        vm.stopPrank();

        assertEq(yieldToken.balanceOf(streamer), 97.5 ether);
        assertEq(tokenA.balanceOf(feeRecipient), 2.5 ether);
        assertEq(tokenB.balanceOf(address(yieldToken)), 97.5 ether);
    }

    function testDonateETH_Yield() public {
        vm.startPrank(superAdmin);
        donation.setYieldConfig(address(yieldToken), address(tokenB), address(0), true, 0);
        donation.setStreamerYieldContract(streamer, address(yieldToken));
        vm.stopPrank();

        vm.prank(donor);
        donation.donate{value: 1 ether}(donor, address(0), 0, streamer, 0, block.timestamp + 10);

        assertEq(yieldToken.balanceOf(streamer), 0.975 ether);
        assertEq(tokenB.balanceOf(address(yieldToken)), 0.975 ether);
        assertEq(feeRecipient.balance, 0.025 ether);
    }
}
