// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/KubiStreamerDonation.sol";
import "../contracts/interfaces/IERC20.sol";
import "../contracts/interfaces/IYieldWrapper.sol";
import "../contracts/interfaces/IUniswapV3SwapRouter.sol";

// ═══════════════════════════════════════════════════════════════════════
// MOCK CONTRACTS (reused from existing test)
// ═══════════════════════════════════════════════════════════════════════

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

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "ALLOWANCE");
            allowance[from][msg.sender] = allowed - value;
        }
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }
}

contract MockFactory {
    mapping(address => mapping(address => mapping(uint24 => address))) pools;

    function getPool(address a, address b, uint24 fee) external view returns (address) {
        return pools[a][b][fee];
    }

    function setPool(address a, address b, uint24 fee, address pool) external {
        pools[a][b][fee] = pool;
        pools[b][a][fee] = pool;
    }
}

contract MockRouter is IUniswapV3SwapRouter {
    address public immutable override WETH9;
    MockFactory public immutable f;

    constructor(address _weth, address _factory) {
        WETH9 = _weth;
        f = MockFactory(_factory);
    }

    function factory() external view override returns (address) {
        return address(f);
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        if (msg.value > 0) {
            require(params.tokenIn == WETH9, "ETH_INPUT_REQUIRES_WETH");
            require(msg.value == params.amountIn, "MISMATCH_MSG_VALUE");
        } else {
            require(
                IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn), "ROUTER_PULL_FAIL"
            );
        }

        require(IERC20(params.tokenOut).transfer(params.recipient, params.amountIn), "ROUTER_SEND_FAIL");
        amountOut = params.amountIn;
    }

    receive() external payable {}
}

contract MockYieldToken is IERC20, IYieldWrapper {
    string public name = "MockYield";
    string public symbol = "MYIELD";
    uint8 public override decimals = 18;
    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    IERC20 public immutable UNDERLYING_TOKEN;
    address public owner;
    address public depositor;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(IERC20 _underlying) {
        UNDERLYING_TOKEN = _underlying;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    function underlying() external view override returns (address) {
        return address(UNDERLYING_TOKEN);
    }

    function setDepositor(address _depositor) external onlyOwner {
        depositor = _depositor;
    }

    function depositYield(address user, uint256 amount) external override {
        require(msg.sender == depositor, "NOT_DEPOSITOR");
        require(amount > 0, "INVALID_AMOUNT");
        require(UNDERLYING_TOKEN.transferFrom(msg.sender, address(this), amount), "TRANSFER_FAIL");
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

// ═══════════════════════════════════════════════════════════════════════
// MOCK HYPERLANE TOKEN (simulates TokenHypERC20 behavior)
// ═══════════════════════════════════════════════════════════════════════

contract MockHyperlaneToken is MockERC20 {
    uint32 public immutable localDomain;
    
    constructor(uint256 supply, uint32 _localDomain) MockERC20(supply) {
        localDomain = _localDomain;
    }
    
    /// @notice Simulate calling handle on recipient after bridging
    function simulateBridgeCallback(
        address recipient,
        uint32 origin,
        address donor,
        address streamer,
        address token,
        uint256 amount
    ) external {
        // Mint tokens to recipient (simulating bridge mint)
        _mint(recipient, amount);
        
        // Encode message payload
        bytes memory message = abi.encode(donor, streamer, token, amount);
        
        // Call handle on recipient
        IHyperlaneRecipient(recipient).handle(
            origin,
            bytes32(uint256(uint160(address(this)))),
            message
        );
    }
}

// ═══════════════════════════════════════════════════════════════════════
// CROSS-CHAIN DONATION TEST CONTRACT
// ═══════════════════════════════════════════════════════════════════════

contract CrossChainDonationTest is Test {
    KubiStreamerDonation donation;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockYieldToken yieldTokenB;
    MockHyperlaneToken hypToken;
    MockRouter router;
    MockFactory factory;
    
    address superAdmin = address(0xAAA);
    address feeRecipient = address(0xFEE);
    address streamer = address(0xBEEF);
    address donor = address(0xCAFE);
    address weth = makeAddr("WETH");
    
    uint32 constant BASE_CHAIN_ID = 84532; // Base Sepolia
    uint32 constant MANTLE_CHAIN_ID = 5003; // Mantle Sepolia
    uint24 constant POOL_FEE = 3000;

    function setUp() public {
        // Deploy infrastructure
        factory = new MockFactory();
        router = new MockRouter(weth, address(factory));

        tokenA = new MockERC20(2_000_000 ether);
        tokenB = new MockERC20(1_000_000 ether);
        yieldTokenB = new MockYieldToken(IERC20(address(tokenB)));
        hypToken = new MockHyperlaneToken(1_000_000 ether, MANTLE_CHAIN_ID);

        // Fund router for swaps
        tokenA.transfer(address(router), 500_000 ether);
        tokenB.transfer(address(router), 500_000 ether);

        // Deploy donation contract
        donation = new KubiStreamerDonation(address(router), superAdmin, 250, feeRecipient);
        yieldTokenB.setDepositor(address(donation));

        // Setup pool
        factory.setPool(address(tokenA), address(tokenB), POOL_FEE, address(0x1));

        // Configure global whitelist
        vm.startPrank(superAdmin);
        donation.setGlobalWhitelist(address(tokenA), true);
        donation.setGlobalWhitelist(address(tokenB), true);
        donation.setGlobalWhitelist(address(hypToken), true);
        donation.setPoolFee(address(hypToken), address(tokenB), POOL_FEE);
        
        // Set trusted remote token (Base Sepolia hypToken)
        donation.setTrustedRemoteToken(BASE_CHAIN_ID, address(hypToken), true);
        vm.stopPrank();
        
        // Configure streamer
        vm.startPrank(superAdmin);
        donation.setStreamerWhitelist(streamer, address(hypToken), true);
        donation.setStreamerWhitelist(streamer, address(tokenB), true);
        donation.setPrimaryToken(streamer, address(tokenB));
        vm.stopPrank();
        
        // Fund hypToken to donation contract (simulating bridged tokens)
        hypToken.mint(address(donation), 100_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // POSITIVE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testBridgedDonation_Direct() public {
        uint256 amount = 100 ether;
        uint256 streamerBalBefore = hypToken.balanceOf(streamer);
        
        // Encode message
        bytes memory message = abi.encode(donor, streamer, address(hypToken), amount);
        bytes32 sender = bytes32(uint256(uint160(address(hypToken))));
        
        // Call handle directly (simulating Hyperlane delivery)
        donation.handle(BASE_CHAIN_ID, sender, message);
        
        // Verify streamer received tokens
        assertEq(hypToken.balanceOf(streamer), streamerBalBefore + amount);
    }

    function testBridgedDonation_EmitsCorrectEvents() public {
        uint256 amount = 100 ether;
        
        bytes memory message = abi.encode(donor, streamer, address(hypToken), amount);
        bytes32 sender = bytes32(uint256(uint160(address(hypToken))));
        
        // Expect events
        vm.expectEmit(true, true, true, false);
        emit KubiStreamerDonation.BridgedDonationReceived(
            BASE_CHAIN_ID,
            donor,
            streamer,
            address(hypToken),
            amount,
            bytes32(0) // messageId will be different
        );
        
        donation.handle(BASE_CHAIN_ID, sender, message);
    }

    function testBridgedDonation_WithYield() public {
        // Configure yield
        vm.startPrank(superAdmin);
        donation.setYieldConfig(address(yieldTokenB), address(tokenB), true, 0);
        donation.setStreamerYieldContract(streamer, address(yieldTokenB));
        donation.setStreamerActiveYield(streamer, address(yieldTokenB));
        vm.stopPrank();
        
        // Fund donation contract with tokenB for yield
        tokenB.transfer(address(donation), 1000 ether);
        
        uint256 amount = 100 ether;
        bytes memory message = abi.encode(donor, streamer, address(tokenB), amount);
        
        // Set tokenB as trusted remote
        vm.prank(superAdmin);
        donation.setTrustedRemoteToken(BASE_CHAIN_ID, address(tokenB), true);
        
        bytes32 sender = bytes32(uint256(uint160(address(tokenB))));
        
        // Call handle
        donation.handle(BASE_CHAIN_ID, sender, message);
        
        // Verify yield token minted for streamer
        assertGt(yieldTokenB.balanceOf(streamer), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // REPLAY PROTECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testBridgedDonation_ReplayProtection() public {
        uint256 amount = 100 ether;
        
        bytes memory message = abi.encode(donor, streamer, address(hypToken), amount);
        bytes32 sender = bytes32(uint256(uint160(address(hypToken))));
        
        // First call succeeds
        donation.handle(BASE_CHAIN_ID, sender, message);
        
        // Second call with same message in same block should fail
        vm.expectRevert(abi.encodeWithSelector(MessageAlreadyProcessed.selector));
        donation.handle(BASE_CHAIN_ID, sender, message);
    }

    function testBridgedDonation_DifferentBlocksAllowed() public {
        uint256 amount = 100 ether;
        
        bytes memory message = abi.encode(donor, streamer, address(hypToken), amount);
        bytes32 sender = bytes32(uint256(uint160(address(hypToken))));
        
        // First call
        donation.handle(BASE_CHAIN_ID, sender, message);
        
        // Move to next block
        vm.roll(block.number + 1);
        
        // Second call with different block number should succeed (different messageId)
        donation.handle(BASE_CHAIN_ID, sender, message);
        
        // Verify streamer received both donations
        assertEq(hypToken.balanceOf(streamer), 200 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // NEGATIVE TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testBridgedDonation_RevertUntrustedOrigin() public {
        uint256 amount = 100 ether;
        
        bytes memory message = abi.encode(donor, streamer, address(hypToken), amount);
        bytes32 sender = bytes32(uint256(uint160(address(hypToken))));
        
        // Call from untrusted chain ID
        vm.expectRevert(abi.encodeWithSelector(UntrustedRemoteToken.selector));
        donation.handle(12345, sender, message); // Unknown chain ID
    }

    function testBridgedDonation_RevertUntrustedToken() public {
        uint256 amount = 100 ether;
        address untrustedToken = address(0xDEAD);
        
        bytes memory message = abi.encode(donor, streamer, untrustedToken, amount);
        bytes32 sender = bytes32(uint256(uint160(untrustedToken)));
        
        vm.expectRevert(abi.encodeWithSelector(UntrustedRemoteToken.selector));
        donation.handle(BASE_CHAIN_ID, sender, message);
    }

    function testBridgedDonation_RevertZeroAmount() public {
        bytes memory message = abi.encode(donor, streamer, address(hypToken), uint256(0));
        bytes32 sender = bytes32(uint256(uint160(address(hypToken))));
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));
        donation.handle(BASE_CHAIN_ID, sender, message);
    }

    function testBridgedDonation_RevertZeroStreamer() public {
        uint256 amount = 100 ether;
        
        bytes memory message = abi.encode(donor, address(0), address(hypToken), amount);
        bytes32 sender = bytes32(uint256(uint160(address(hypToken))));
        
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        donation.handle(BASE_CHAIN_ID, sender, message);
    }

    function testBridgedDonation_RevertInvalidMessageFormat() public {
        bytes memory shortMessage = abi.encode(donor, streamer); // Too short
        bytes32 sender = bytes32(uint256(uint160(address(hypToken))));
        
        vm.expectRevert(abi.encodeWithSelector(InvalidMessageFormat.selector));
        donation.handle(BASE_CHAIN_ID, sender, shortMessage);
    }

    function testBridgedDonation_RevertTokenNotWhitelisted() public {
        uint256 amount = 100 ether;
        address unlistedToken = address(new MockERC20(1000 ether));
        
        // Set as trusted remote but not in global whitelist
        vm.prank(superAdmin);
        donation.setTrustedRemoteToken(BASE_CHAIN_ID, unlistedToken, true);
        
        bytes memory message = abi.encode(donor, streamer, unlistedToken, amount);
        bytes32 sender = bytes32(uint256(uint160(unlistedToken)));
        
        vm.expectRevert(abi.encodeWithSelector(NotInGlobalWhitelist.selector));
        donation.handle(BASE_CHAIN_ID, sender, message);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PENDING DONATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testClaimPendingDonation_ByDonor() public {
        // Create a pending donation by making processing fail
        // For this test, we'll manually set a pending donation
        
        bytes32 testMessageId = keccak256("test_message");
        
        // We can't directly set pending donations, so this test is limited
        // In real scenario, pending donations are created when processing fails
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ADMIN TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testSetTrustedRemoteToken() public {
        address newToken = address(0x1234);
        uint32 chainId = 8453; // Base mainnet
        
        vm.prank(superAdmin);
        vm.expectEmit(true, true, false, true);
        emit KubiStreamerDonation.TrustedTokenUpdated(chainId, newToken, true);
        donation.setTrustedRemoteToken(chainId, newToken, true);
        
        assertTrue(donation.trustedRemoteTokens(chainId, newToken));
    }

    function testSetTrustedRemoteToken_RevertZeroAddress() public {
        vm.prank(superAdmin);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        donation.setTrustedRemoteToken(BASE_CHAIN_ID, address(0), true);
    }

    function testSetTrustedRemoteToken_OnlyOwnerOrSuper() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(OnlyOwnerOrSuper.selector));
        donation.setTrustedRemoteToken(BASE_CHAIN_ID, address(0x1234), true);
    }
}
