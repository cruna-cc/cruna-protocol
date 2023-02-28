const {expect} = require("chai");
const {deployContractUpgradeable, deployContract, amount, assertThrowsMessage} = require("./helpers");

describe("Integration", function () {
  let e2, e2Protected;
  let assetRegistry;
  // mocks
  let bulls, particle, fatBelly, stupidMonk, uselessWeapons;
  // wallets
  let defWallet, deployer, bob, alice, fred, john, jane, e2Owner, trtOwner, mark;

  before(async function () {
    [deployer, bob, alice, fred, john, jane, e2Owner, trtOwner, mark] = await ethers.getSigners();
  });

  function transferNft(nft, user) {
    return nft.connect(user)["safeTransferFrom(address,address,uint256)"];
  }

  beforeEach(async function () {
    assetRegistry = await deployContract("AssetRegistry");

    e2 = await deployContractUpgradeable("Everdragons2Protector", [e2Owner.address], {from: deployer});
    await e2.connect(e2Owner).safeMint(bob.address, 1);
    await e2.connect(e2Owner).safeMint(bob.address, 2);
    await e2.connect(e2Owner).safeMint(bob.address, 3);
    await e2.connect(e2Owner).safeMint(bob.address, 4);
    await e2.connect(e2Owner).safeMint(alice.address, 5);
    await e2.connect(e2Owner).safeMint(alice.address, 6);

    e2Protected = await deployContractUpgradeable("Protected", [e2.address, assetRegistry.address]);
    await assetRegistry.registerProtected(e2Protected.address);

    // erc20
    bulls = await deployContract("Bulls");
    await bulls.mint(bob.address, amount("90000"));
    await bulls.mint(john.address, amount("60000"));
    await bulls.mint(jane.address, amount("100000"));
    await bulls.mint(alice.address, amount("100000"));
    await bulls.mint(fred.address, amount("100000"));

    fatBelly = await deployContract("FatBelly");
    await fatBelly.mint(alice.address, amount("10000000"));
    await fatBelly.mint(john.address, amount("2000000"));
    await fatBelly.mint(fred.address, amount("30000000"));

    // erc721
    particle = await deployContract("Particle");
    await particle.safeMint(alice.address, 1);
    await particle.safeMint(bob.address, 2);
    await particle.safeMint(john.address, 3);

    stupidMonk = await deployContract("StupidMonk");
    await stupidMonk.safeMint(bob.address, 1);
    await stupidMonk.safeMint(alice.address, 2);
    await stupidMonk.safeMint(john.address, 3);

    // erc1155
    uselessWeapons = await deployContract("UselessWeapons");
    await uselessWeapons.mintBatch(bob.address, [1, 2], [5, 2], "0x00");
    await uselessWeapons.mintBatch(alice.address, [2], [2], "0x00");
    await uselessWeapons.mintBatch(john.address, [3, 4], [10, 1], "0x00");
  });

  async function configure(protectorId, allowAll_, allowWithConfirmation_, allowList_, allowListStatus_) {
    await e2Protected.configure(protectorId, allowAll_, allowWithConfirmation_, allowList_, allowListStatus_);
  }

  it("should allow the deployer to upgrade the contract", async function () {
    expect(await e2.version()).equal("1.0.0");
    const e2V2 = await ethers.getContractFactory("Everdragons2ProtectorV2");
    const newImplementation = await e2V2.deploy();
    await newImplementation.deployed();
    expect(await newImplementation.getId()).equal("0xf98e5a0b");
    await e2.connect(deployer).upgradeTo(newImplementation.address);
    expect(await e2.version()).equal("2.0.0");
  });

  it("should not allow the owner to upgrade the contract", async function () {
    expect(await e2.version()).equal("1.0.0");
    const e2V2 = await ethers.getContractFactory("Everdragons2ProtectorV2");
    const newImplementation = await e2V2.deploy();
    await newImplementation.deployed();
    await assertThrowsMessage(e2.connect(e2Owner).upgradeTo(newImplementation.address), "NotTheContractDeployer()");
  });

  it("should create a vault and add more assets to it", async function () {
    // bob creates a vault depositing a particle token
    await particle.connect(bob).setApprovalForAll(e2Protected.address, true);
    await e2Protected.connect(bob).depositNFT(1, particle.address, 2);
    expect(await e2Protected.ownedAssetAmount(1, particle.address, 2)).equal(1);

    // bob adds a stupidMonk token to his vault
    await stupidMonk.connect(bob).setApprovalForAll(e2Protected.address, true);
    await e2Protected.connect(bob).depositNFT(1, stupidMonk.address, 1);
    expect(await e2Protected.ownedAssetAmount(1, stupidMonk.address, 1)).equal(1);

    // bob adds some bulls tokens to his vault
    await bulls.connect(bob).approve(e2Protected.address, amount("10000"));
    await e2Protected.connect(bob).depositFT(1, bulls.address, amount("5000"));
    expect(await e2Protected.ownedAssetAmount(1, bulls.address, 0)).equal(amount("5000"));

    // the protected cannot be transferred
    await expect(transferNft(e2Protected, bob)(bob.address, alice.address, 1)).revertedWith(
      "ERC721Subordinate: transfers not allowed"
    );

    // bob transfers the protector to alice
    await expect(transferNft(e2, bob)(bob.address, alice.address, 1))
      .emit(e2, "Transfer")
      .withArgs(bob.address, alice.address, 1);
  });

  it("should allow a transfer if a transfer initializer is pending", async function () {
    // bob creates a vault depositing a particle token
    await particle.connect(bob).setApprovalForAll(e2Protected.address, true);
    await e2Protected.connect(bob).depositNFT(1, particle.address, 2);
    expect(await e2Protected.ownedAssetAmount(1, particle.address, 2)).equal(1);

    await expect(e2.connect(bob).setStarter(mark.address)).emit(e2, "StarterStarted").withArgs(bob.address, mark.address, true);

    // bob transfers the protector to alice
    await expect(transferNft(e2, bob)(bob.address, alice.address, 1))
      .emit(e2, "Transfer")
      .withArgs(bob.address, alice.address, 1);
  });

  it("should not allow a transfer if a transfer initializer is active", async function () {
    // bob creates a vault depositing a particle token
    await particle.connect(bob).setApprovalForAll(e2Protected.address, true);
    await e2Protected.connect(bob).depositNFT(1, particle.address, 2);
    expect(await e2Protected.ownedAssetAmount(1, particle.address, 2)).equal(1);

    await expect(e2.connect(bob).setStarter(mark.address)).emit(e2, "StarterStarted").withArgs(bob.address, mark.address, true);

    await expect(e2.connect(mark).confirmStarter(bob.address))
      .emit(e2, "StarterUpdated")
      .withArgs(bob.address, mark.address, true);

    await expect(transferNft(e2, bob)(bob.address, alice.address, 1)).revertedWith("TransferNotPermitted()");
  });

  it("should allow a transfer if the transfer initializer starts it", async function () {
    // bob creates a vault depositing a particle token
    await particle.connect(bob).setApprovalForAll(e2Protected.address, true);
    await e2Protected.connect(bob).depositNFT(1, particle.address, 2);
    expect(await e2Protected.ownedAssetAmount(1, particle.address, 2)).equal(1);

    await expect(e2.connect(bob).setStarter(mark.address)).emit(e2, "StarterStarted").withArgs(bob.address, mark.address, true);

    await expect(e2.connect(mark).confirmStarter(bob.address))
      .emit(e2, "StarterUpdated")
      .withArgs(bob.address, mark.address, true);

    await expect(e2.connect(mark).startTransfer(1, alice.address, 1000))
      .emit(e2, "TransferStarted")
      .withArgs(mark.address, 1, alice.address);

    await expect(e2.connect(bob).completeTransfer(1)).emit(e2, "Transfer").withArgs(bob.address, alice.address, 1);

    expect(await e2.ownerOf(1)).equal(alice.address);
    expect(await e2Protected.ownerOf(1)).equal(alice.address);
  });
});
