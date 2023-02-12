const {expect} = require("chai");
const {deployContractUpgradeable, deployContract, number} = require("./helpers");

describe("Integration", function () {
  let e2;
  let protectedToken;
  // mocks
  let bulls;
  let particel;
  let fatBelly
  let stupidMonk
  let uselessWeapons

  let owner, bob, alice, fred, john, jane;

  before(async function () {
    [owner, bob, alice, fred, john, jane] = await ethers.getSigners();
  });

  beforeEach(async function () {
    e2 = await deployContractUpgradeable("Everdragons2Protector");

    await e2.safeMint(bob.address, 1);
    await e2.safeMint(bob.address, 2);
    await e2.safeMint(bob.address, 3);
    await e2.safeMint(bob.address, 4);
    await e2.safeMint(alice.address, 5);
    await e2.safeMint(alice.address, 6);

    protectedToken = await deployContractUpgradeable("Protected", [e2.address]);

    bulls = await deployContract("Bulls");
    fatBelly = await deployContract("FatBelly");
    particel = await deployContract("Particel");
    stupidMonk = await deployContract("StupidMonk");
    uselessWeapons = await deployContract("UselessWeapons");

  });

  async function configure(protectorId, allowAll_, allowWithConfirmation_, allowList_, allowListStatus_) {
    await protectedToken.configure(protectorId, allowAll_, allowWithConfirmation_, allowList_, allowListStatus_);
  }

  it("should verify the flow", async function () {
  });
});
