const {expect} = require("chai");
const { deployContractUpgradeable, deployContract, number} = require("./helpers");

describe("Subordinate", function () {
  let myToken;
  let myTokenEnumerable;

  let subordinate;
  let subordinateEnumerableUpgradeable;

  let owner, holder1, holder2, holder3;

  before(async function () {
    [owner, holder1, holder2, holder3] = await ethers.getSigners();
  });

  beforeEach(async function () {
    myToken = await deployContract("MyToken");

    await myToken.safeMint(holder1.address, 1)
    await myToken.safeMint(holder1.address, 2)
    await myToken.safeMint(holder1.address, 3)

    myTokenEnumerable = await deployContract("MyTokenEnumerable");

    await myTokenEnumerable.safeMint(holder1.address, 1)
    await myTokenEnumerable.safeMint(holder1.address, 3)
    await myTokenEnumerable.safeMint(holder1.address, 2)

    subordinate = await deployContract("MySubordinate", myToken.address);
    subordinateEnumerableUpgradeable = await deployContractUpgradeable("MySubordinateEnumerableUpgradeable", [myTokenEnumerable.address]);

  });

  it("should verify the flow for ERC721Subordinate", async function () {

    expect(await myToken.balanceOf(holder1.address)).equal(3)
    expect(await subordinate.balanceOf(holder1.address)).equal(3)

    expect(await myToken.ownerOf(1)).equal(holder1.address);
    expect(await subordinate.ownerOf(1)).equal(holder1.address);

    expect(await myToken.balanceOf(holder2.address)).equal(0)
    expect(await subordinate.balanceOf(holder2.address)).equal(0)

    await myToken.connect(holder1)["safeTransferFrom(address,address,uint256)"](holder1.address, holder2.address, 1)

    expect(await myToken.balanceOf(holder1.address)).equal(2)
    expect(await subordinate.balanceOf(holder1.address)).equal(2)

    expect(await myToken.ownerOf(1)).equal(holder2.address);
    expect(await subordinate.ownerOf(1)).equal(holder2.address);

    expect(await myToken.balanceOf(holder2.address)).equal(1)
    expect(await subordinate.balanceOf(holder2.address)).equal(1)

    expect(await subordinate.getInterfaceId()).equal("0x60c8f291")

  });

  it("should verify the flow for ERC721EnumerableSubordinateUpgradeable", async function () {

    const max1 = await number(subordinateEnumerableUpgradeable.totalSupply())
    const max2 = await number(myTokenEnumerable.totalSupply())

    expect(max1).equal(max2)

    expect(await myTokenEnumerable.balanceOf(holder1.address)).equal(3)
    expect(await subordinateEnumerableUpgradeable.balanceOf(holder1.address)).equal(3)

    expect(await myTokenEnumerable.ownerOf(1)).equal(holder1.address);
    expect(await subordinateEnumerableUpgradeable.ownerOf(1)).equal(holder1.address);

    expect(await myTokenEnumerable.balanceOf(holder2.address)).equal(0)
    expect(await subordinateEnumerableUpgradeable.balanceOf(holder2.address)).equal(0)

    expect(await myTokenEnumerable.tokenOfOwnerByIndex(holder1.address, 1)).equal(3)
    expect(await subordinateEnumerableUpgradeable.tokenOfOwnerByIndex(holder1.address, 1)).equal(3)

    expect(await myTokenEnumerable.tokenByIndex(1)).equal(3)
    expect(await subordinateEnumerableUpgradeable.tokenByIndex(1)).equal(3)

    await myTokenEnumerable.connect(holder1)["safeTransferFrom(address,address,uint256)"](holder1.address, holder2.address, 1)

    expect(await myTokenEnumerable.balanceOf(holder1.address)).equal(2)
    expect(await subordinateEnumerableUpgradeable.balanceOf(holder1.address)).equal(2)

    expect(await myTokenEnumerable.ownerOf(1)).equal(holder2.address);
    expect(await subordinateEnumerableUpgradeable.ownerOf(1)).equal(holder2.address);

    expect(await myTokenEnumerable.balanceOf(holder2.address)).equal(1)
    expect(await subordinateEnumerableUpgradeable.balanceOf(holder2.address)).equal(1)

    expect(await subordinateEnumerableUpgradeable.getInterfaceId()).equal("0x60c8f291")
  });

});
