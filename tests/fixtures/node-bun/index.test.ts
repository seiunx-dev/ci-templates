import { expect, test } from "bun:test";
import { add } from "./index";

test("add", () => expect(add(2, 2)).toBe(4));
