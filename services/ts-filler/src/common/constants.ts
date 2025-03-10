import { zeroAddress, type Address, type Hex } from "viem";

export default {
  slots: {
    anchorStateRegistrySlot:
      "0xa6eef7e35abe7026729641147f7915573c7e97b47efa546f5f6e3230263bcb49",
    fulfillmentInfoSlot:
      "0x40f2eef6aad3cb0e74d3b59b45d3d5f2d5fc8dc382e739617b693cdd4bc30c00",
  },
  mockL1StateRootProof: [
    "0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563",
    "0xb10e2d527612073b26eecdfd717e6a320cf44b4afac2b0732d9fcbe2b7fa0cf6",
    "0x405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ace",
    "0xc2575a0e9e593c00f959f8c92f12db2869c3395a3b0502d05e2516446f71f85b",
    "0x8a35acfbc15ff81a39ae7d344fd709f28e8600b4aa8c65c6b64bfe7fe36bd19b",
    "0x036b6384b5eca791c62761152d0c79bb0604c104a5fb6f4eb0703f3154bb3db0",
    "0xf652222313e28459528d920b65115c16c04f3efc82aaedc97be59f3f377c0d3f",
    "0xa66cc928b5edb82af9bd49922954155ab7b0942694bea4ce44661d9a8736c688",
    "0xf3f7a9fe364faab93b216da50a3214154f22a0a2b415b23a84c8169e8b636ee3",
    "0x6e1540171b6c0c960b71a7020d9f60077f6af931a8bbf590da0223dacf75c7af",
    "0xc65a7bb8d6351c1cf70c95a316cc6a92839c986682d98bc35f958f4883f9d2a8",
    "0x0175b7a638427703f0dbe7bb9bbf987a2551717b34e79f33b5b1008d1fa01db9",
  ],
  mockAccount: "0x2c4d5B2d8B7ba9e15F09Da8fD455E312bF774Eeb",
  ethAddress: zeroAddress,
} as {
  slots: Record<string, Hex>;
  mockL1StateRootProof: Hex[];
  mockAccount: Address;
  ethAddress: Address;
};
