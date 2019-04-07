{ lib }:

rec {
  /**
   * >>> singleton 1
   * [1]
   * >>> singleton [1]
   * [[1]]
   */
  singleton = x: [ x ];

  /**
   * >>> singleton1 1
   * [1]
   * >>> singleton1 [1]
   * [1]
   */
  singleton1 = x: if builtins.isList x then x else [ x ];

  /**
   * >>> ifThenList false 1
   * []
   * >>> ifThenList true 1
   * [1]
   * >>> ifThenList true [1]
   * [1]
   */
  ifThenList = cond: elt: if cond then singleton1 elt else [ ];

  /**
   * >>> isNonEmptyList []
   * true
   * >>> isNonEmptyList 0
   * false
   */
  isNonEmptyList = obj: builtins.isList obj && obj != [];

  /**
   * >>> replicate 1 0
   * [0]
   * >>> replicate 0 0
   * []
   * >>> replicate 2 0
   * [0, 0]
   */
  replicate = n: obj: builtins.genList (_: obj) n;
}
