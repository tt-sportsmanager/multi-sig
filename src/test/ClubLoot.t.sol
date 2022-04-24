// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4;

import {IClub} from "../interfaces/IClub.sol";
import {IRicardianLLC} from "../interfaces/IRicardianLLC.sol";

import {KaliClubSig, Signature} from "../KaliClubSig.sol";
import {ClubLoot} from "../ClubLoot.sol";
import {KaliClubSigFactory} from "../KaliClubSigFactory.sol";

import "@std/Test.sol";

contract ClubLootTest is Test {
    using stdStorage for StdStorage;

    KaliClubSig clubSig;
    ClubLoot loot;
    KaliClubSigFactory factory;

    /// @dev Users

    uint256 immutable alicesPk =
        0x60b919c82f0b4791a5b7c6a7275970ace1748759ebdaa4076d7eeed9dbcff3c3;
    address public immutable alice = 0x503408564C50b43208529faEf9bdf9794c015d52;

    uint256 immutable bobsPk =
        0xf8f8a2f43c8376ccb0871305060d7b27b0554d2cc72bccf41b2705608452f315;
    address public immutable bob = 0x001d3F1ef827552Ae1114027BD3ECF1f086bA0F9;

    uint256 immutable charliesPk =
        0xb9dee2522aae4d21136ba441f976950520adf9479a3c0bda0a88ffc81495ded3;
    address public immutable charlie = 0xccc4A5CeAe4D88Caf822B355C02F9769Fb6fd4fd;

    uint256 immutable nullPk =
        0x8b2ed20f3cc3dd482830910365cfa157e7568b9c3fa53d9edd3febd61086b9be;
    address public immutable nully = 0x0ACDf2aC839B7ff4cd5F16e884B2153E902253f2;

    /// @dev Integrations

    IRicardianLLC public immutable ricardian =
        IRicardianLLC(0x2017d429Ad722e1cf8df9F1A2504D4711cDedC49);

    /// @dev Helpers

    bytes32 name = 0x5445535400000000000000000000000000000000000000000000000000000000;
    bytes32 symbol = 0x5445535400000000000000000000000000000000000000000000000000000000;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function signPermit(uint256 pk, bytes32 digest) internal returns (uint8 v, bytes32 r, bytes32 s) {
        (v, r, s) = vm.sign(
            pk,
            digest
        );
    }

    /// -----------------------------------------------------------------------
    /// Club Setup Tests
    /// -----------------------------------------------------------------------

    /// @notice Set up the testing suite

    function setUp() public {
        clubSig = new KaliClubSig();
        loot = new ClubLoot();

        // Create the factory
        factory = new KaliClubSigFactory(clubSig, loot, ricardian);

        // Create the Club[]
        IClub.Club[] memory clubs = new IClub.Club[](2);
        clubs[0] = alice > bob
            ? IClub.Club(bob, 1, 100)
            : IClub.Club(alice, 0, 100);
        clubs[1] = alice > bob
            ? IClub.Club(alice, 0, 100)
            : IClub.Club(bob, 1, 100);

        // The factory is fully tested in KaliClubSigFactory.t.sol
        (clubSig, loot) = factory.deployClubSig(
            clubs,
            2,
            0,
            name,
            symbol,
            false,
            false,
            "BASE",
            "DOCS"
        );
    }

    /// -----------------------------------------------------------------------
    /// Club Loot Tests
    /// -----------------------------------------------------------------------

    function testInvariantMetadata() public {
        assertEq(loot.name(), string(abi.encodePacked(name, " LOOT")));
        assertEq(loot.symbol(), string(abi.encodePacked(symbol, "-LOOT")));
        assertEq(loot.decimals(), 18);  
    }

    function testApprove() public {
        assertTrue(loot.approve(address(0xBEEF), 1e18));
        assertEq(loot.allowance(address(this), address(0xBEEF)), 1e18);
    }

    function testTransfer() public {
        startHoax(alice, alice, type(uint256).max);
        assertTrue(loot.transfer(address(0xBEEF), 10));
        vm.stopPrank();

        assertEq(loot.totalSupply(), 200);
        assertEq(loot.balanceOf(alice), 90);
        assertEq(loot.balanceOf(address(0xBEEF)), 10);
    }

    function testTransferFrom() public {
        startHoax(alice, alice, type(uint256).max);
        assertTrue(loot.approve(bob, 10));
        vm.stopPrank();

        assertEq(loot.allowance(alice, bob), 10);

        startHoax(bob, bob, type(uint256).max);
        assertTrue(loot.transferFrom(alice, charlie, 10));
        vm.stopPrank();

        assertEq(loot.allowance(alice, bob), 0);
        assertEq(loot.balanceOf(alice), 90);
        assertEq(loot.balanceOf(charlie), 10);
    }

    function testBurn() public {
        startHoax(bob, bob, type(uint256).max);
        loot.burn(10);
        vm.stopPrank();

        assertEq(loot.balanceOf(bob), 90);
        assert(loot.totalSupply() == 190);
    }

    function testBurnFrom() public {
        startHoax(alice, alice, type(uint256).max);
        assertTrue(loot.approve(bob, 10));
        vm.stopPrank();

        assertEq(loot.allowance(alice, bob), 10);

        startHoax(bob, bob, type(uint256).max);
        loot.burnFrom(alice, 10);
        vm.stopPrank();

        assertEq(loot.allowance(alice, bob), 0);
        assertEq(loot.balanceOf(alice), 90);
        assert(loot.totalSupply() == 190);
    }

    function testGovernance() public {
        assert(loot.governance() == address(clubSig)); 

        startHoax(alice, alice, type(uint256).max);
        vm.expectRevert(bytes4(keccak256("NotGov()")));
        loot.setGov(alice);
        vm.stopPrank();

        startHoax(address(clubSig), address(clubSig), type(uint256).max);
        loot.setGov(alice);
        vm.stopPrank();

        assert(loot.governance() == alice); 

        startHoax(alice, alice, type(uint256).max);
        loot.setGov(bob);
        vm.stopPrank();

        assert(loot.governance() == bob);
    }

    function testMint() public {
        address db = address(0xdeadbeef);

        IClub.Club[] memory clubs = new IClub.Club[](1);
        clubs[0] = IClub.Club(db, 2, 100);

        bool[] memory mints = new bool[](1);
        mints[0] = true;

        vm.prank(address(clubSig));
        clubSig.govern(clubs, mints, 3);
        assert(loot.balanceOf(db) == 100);
        assert(loot.totalSupply() == 300);

        vm.prank(address(clubSig));
        loot.mint(alice, 100);
        assert(loot.balanceOf(alice) == 200);
        assert(loot.totalSupply() == 400);
    }

    function testGovBurn() public {
        startHoax(address(clubSig), address(clubSig), type(uint256).max);
        loot.govBurn(alice, 50);
        assert(loot.balanceOf(alice) == 50);
        assert(loot.totalSupply() == 150);
        vm.stopPrank();
    }

    function testSetLootPause(bool _paused) public {
        startHoax(address(clubSig), address(clubSig), type(uint256).max);
        clubSig.setLootPause(_paused);
        vm.stopPrank();
        assert(loot.paused() == _paused);
    }

    function testPausedTransfer() public {
        startHoax(address(clubSig), address(clubSig), type(uint256).max);
        clubSig.setLootPause(true);
        vm.stopPrank();

        startHoax(alice, alice, type(uint256).max);
        vm.expectRevert(bytes4(keccak256("Paused()")));
        loot.transfer(address(0xBEEF), 10);
        vm.stopPrank();
    }

    function testPermit() public {
        (uint8 v, bytes32 r, bytes32 s) = signPermit(
            alicesPk,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    loot.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, alice, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        loot.permit(alice, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(loot.allowance(alice, address(0xCAFE)), 1e18);
        assertEq(loot.nonces(alice), 1);
    }
}
