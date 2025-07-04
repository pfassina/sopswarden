#!/usr/bin/env bash

# sopswarden Test Suite Runner
# Runs all tests to validate the flake works correctly

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test output directory
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TEST_DIR/.." && pwd)"

echo -e "${BLUE}🧪 Running sopswarden test suite...${NC}"
echo -e "${BLUE}Test directory: $TEST_DIR${NC}"
echo -e "${BLUE}Root directory: $ROOT_DIR${NC}"
echo ""

# Function to run a single test
run_test() {
    local test_file="$1"
    local test_name="$2"
    local test_description="$3"
    
    echo -e "${BLUE}Running: $test_name${NC}"
    echo -e "${BLUE}Description: $test_description${NC}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Run the test with --impure flag (current implementation requires it)
    if cd "$ROOT_DIR" && nix-instantiate --eval --strict --impure "$test_file" --json > /tmp/test-result.json 2>/tmp/test-error.log; then
        # Parse the result
        if jq -r '.success' /tmp/test-result.json | grep -q "true"; then
            echo -e "${GREEN}✅ PASSED: $test_name${NC}"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}❌ FAILED: $test_name${NC}"
            echo -e "${RED}Test returned success=false${NC}"
            if [[ -s /tmp/test-error.log ]]; then
                echo -e "${RED}Error output:${NC}"
                cat /tmp/test-error.log
            fi
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo -e "${RED}❌ FAILED: $test_name${NC}"
        echo -e "${RED}Test evaluation failed${NC}"
        if [[ -s /tmp/test-error.log ]]; then
            echo -e "${RED}Error output:${NC}"
            cat /tmp/test-error.log
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    echo ""
}

# Function to run flake checks
run_flake_checks() {
    echo -e "${BLUE}Running flake checks...${NC}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if cd "$ROOT_DIR" && nix flake check --no-build 2>/tmp/flake-check-error.log; then
        echo -e "${GREEN}✅ PASSED: Flake validation${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAILED: Flake validation${NC}"
        if [[ -s /tmp/flake-check-error.log ]]; then
            echo -e "${RED}Error output:${NC}"
            cat /tmp/flake-check-error.log
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    echo ""
}

# Function to test package building
test_package_building() {
    echo -e "${BLUE}Testing package building...${NC}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if cd "$ROOT_DIR" && nix build .#sopswarden-sync --no-link 2>/tmp/build-error.log; then
        echo -e "${GREEN}✅ PASSED: Package building${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAILED: Package building${NC}"
        if [[ -s /tmp/build-error.log ]]; then
            echo -e "${RED}Error output:${NC}"
            cat /tmp/build-error.log
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    echo ""
}

# Pre-flight checks
echo -e "${BLUE}Pre-flight checks...${NC}"

# Check if nix is available
if ! command -v nix &> /dev/null; then
    echo -e "${RED}❌ ERROR: nix command not found${NC}"
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ ERROR: jq command not found${NC}"
    exit 1
fi

# Check if we're in the right directory
if [[ ! -f "$ROOT_DIR/flake.nix" ]]; then
    echo -e "${RED}❌ ERROR: flake.nix not found in $ROOT_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Pre-flight checks passed${NC}"
echo ""

# Run flake validation first
run_flake_checks

# Test package building
test_package_building

# Run core tests
echo -e "${YELLOW}=== CORE TESTS ===${NC}"
run_test "$TEST_DIR/core/test-pure-evaluation.nix" "Core Evaluation" "Tests flake structure and basic functionality"
run_test "$TEST_DIR/core/test-cyclic-dependencies.nix" "Cyclic Dependencies" "Tests that evaluation doesn't create circular dependencies"

# Run workflow tests
echo -e "${YELLOW}=== WORKFLOW TESTS ===${NC}"
run_test "$TEST_DIR/workflows/test-fresh-install.nix" "Fresh Installation" "Tests user journey for installing sopswarden from scratch"
run_test "$TEST_DIR/workflows/test-add-secrets.nix" "Add Secrets" "Tests user journey for adding new secrets to existing configuration"

# Run module tests
echo -e "${YELLOW}=== MODULE TESTS ===${NC}"
run_test "$TEST_DIR/modules/test-nixos-module.nix" "NixOS Module" "Tests NixOS module integration and secrets usage"
run_test "$TEST_DIR/modules/test-home-manager.nix" "Home Manager Module" "Tests Home Manager module integration"

# Run integration tests
echo -e "${YELLOW}=== INTEGRATION TESTS ===${NC}"
run_test "$TEST_DIR/integration/test-runtime-sync.nix" "Runtime Sync" "Tests sync script generation and application access"
run_test "$TEST_DIR/integration/test-rbw-states.nix" "RBW States" "Tests handling of rbw locked/unlocked/unavailable states"

# Test library functions directly
echo -e "${YELLOW}=== LIBRARY TESTS ===${NC}"
echo -e "${BLUE}Testing library functions...${NC}"

TOTAL_TESTS=$((TOTAL_TESTS + 1))

if cd "$ROOT_DIR" && nix-instantiate --eval --strict --impure -E '
let
  flake = builtins.getFlake (toString ./.);
  pkgs = import <nixpkgs> {};
  
  # Test all library functions
  testLib = {
    mkSyncScript = builtins.isFunction flake.lib.mkSyncScript;
    mkSopsSecrets = builtins.isFunction flake.lib.mkSopsSecrets;
    mkSecretAccessors = builtins.isFunction flake.lib.mkSecretAccessors;
    mkHashTracker = builtins.isFunction flake.lib.mkHashTracker;
    normalizeSecretDef = builtins.isFunction flake.lib.normalizeSecretDef;
    
    # Test normalization
    simpleNorm = flake.lib.normalizeSecretDef "test";
    complexNorm = flake.lib.normalizeSecretDef { name = "test"; user = "user"; };
    
    # Test sync script creation
    syncScript = flake.lib.mkSyncScript { inherit pkgs; };
  };
  
  success = testLib.mkSyncScript && testLib.mkSopsSecrets && testLib.mkSecretAccessors && 
            testLib.mkHashTracker && testLib.normalizeSecretDef && 
            testLib.simpleNorm.name == "test" && testLib.complexNorm.user == "user" &&
            builtins.isAttrs testLib.syncScript;
in
{ inherit success; result = testLib; }
' --json > /tmp/lib-test-result.json 2>/tmp/lib-test-error.log; then
    if jq -r '.success' /tmp/lib-test-result.json | grep -q "true"; then
        echo -e "${GREEN}✅ PASSED: Library Functions${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAILED: Library Functions${NC}"
        echo -e "${RED}Library functions test failed${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo -e "${RED}❌ FAILED: Library Functions${NC}"
    echo -e "${RED}Library functions evaluation failed${NC}"
    if [[ -s /tmp/lib-test-error.log ]]; then
        echo -e "${RED}Error output:${NC}"
        cat /tmp/lib-test-error.log
    fi
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo ""

# Clean up temporary files
rm -f /tmp/test-result.json /tmp/test-error.log /tmp/flake-check-error.log /tmp/build-error.log /tmp/lib-test-result.json /tmp/lib-test-error.log

# Summary
echo -e "${YELLOW}=== TEST SUMMARY ===${NC}"
echo -e "${BLUE}Total tests: $TOTAL_TESTS${NC}"
echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
echo -e "${RED}Failed: $FAILED_TESTS${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    echo -e "${GREEN}🎉 sopswarden is working correctly${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed${NC}"
    echo -e "${RED}🔧 Please check the error messages above${NC}"
    exit 1
fi