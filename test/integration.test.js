const {expect} = require("chai");
const {deployContractUpgradeable, deployContract} = require("./helpers");

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
    await e2.safeMint(bob.address, 1);
    await e2.safeMint(bob.address, 2);
    await e2.safeMint(bob.address, 3);
    await e2.safeMint(bob.address, 4);
    await e2.safeMint(alice.address, 5);
    await e2.safeMint(alice.address, 6);

    e2Protected = await deployContractUpgradeable("Protected", [e2.address]);

    bulls = await deployContract("Bulls");
    fatBelly = await deployContract("FatBelly");
    particle = await deployContract("Particle");
    stupidMonk = await deployContract("StupidMonk");
    uselessWeapons = await deployContract("UselessWeapons");
  });

  async function configure(protectorId, allowAll_, allowWithConfirmation_, allowList_, allowListStatus_) {
    await e2Protected.configure(protectorId, allowAll_, allowWithConfirmation_, allowList_, allowListStatus_);
  }

  it("should verify the flow", async function () {});
});
