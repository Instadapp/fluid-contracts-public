// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.36;

import { Structs } from "./structs.sol";

abstract contract Events {
    event LogUpdateWeekSessions(Structs.Session[] sessions);
}
