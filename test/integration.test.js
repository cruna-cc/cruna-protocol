const {expect} = require("chai");
const {deployContractUpgradeable, deployContract, amount} = require("./helpers");

describe("Integration", function () {
  let e2, e2Protected;
  // mocks
  let bulls, particle, fatBelly, stupidMonk, uselessWeapons;
  // wallets
  let owner, bob, alice, fred, john, jane, e2Owner, trtOwner;

  before(async function () {
    [owner, bob, alice, fred, john, jane, e2Owner, trtOwner] = await ethers.getSigners();
  });

  beforeEach(async function () {
    e2 = await deployContractUpgradeable("Everdragons2Protector", [e2Owner.address]);
    await e2.connect(e2Owner).safeMint(bob.address, 1);
    await e2.connect(e2Owner).safeMint(bob.address, 2);
    await e2.connect(e2Owner).safeMint(bob.address, 3);
    await e2.connect(e2Owner).safeMint(bob.address, 4);
    await e2.connect(e2Owner).safeMint(alice.address, 5);
    await e2.connect(e2Owner).safeMint(alice.address, 6);

    e2Protected = await deployContractUpgradeable("Protected", [e2.address]);

    // erc20
    bulls = await deployContract("Bulls");
    await bulls.mint(bob.address, amount("90000"));
    await bulls.mint(john.address, amount("60000"));
    await bulls.mint(jane.address, amount("100000"));

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

  it("should verify the flow", async function () {
    // bob creates a vault depositing some assets
    await particle.connect(bob).setApprovalForAll(e2Protected.address, true);
    await e2Protected.connect(bob).depositAsset(1, particle.address, 2, 1);
    expect(await e2Protected.isOwnerOfAsset(1, particle.address, 2)).to.be.true;

  });
});
