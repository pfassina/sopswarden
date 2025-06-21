#!/usr/bin/env bash
# Test runner for sopswarden

set -euo pipefail

echo "🚀 Running sopswarden test suite..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "\n${YELLOW}📋 Running: $test_name${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✅ $test_name PASSED${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}❌ $test_name FAILED${NC}"
        ((TESTS_FAILED++))
    fi
}

# Change to repository root
cd "$(dirname "$0")/.."

# Test 1: Flake check
run_test "Flake check" "nix flake check --no-build"

# Test 2: Unit tests
run_test "Unit tests" "nix-build tests/unit/test-lib.nix"

# Test 3: NixOS module test
run_test "NixOS module test" "nix-build '<nixpkgs/nixos>' -A system --arg configuration ./tests/nixos/test-module.nix --no-out-link"

# Test 4: Integration test (requires mock setup)
if command -v age &> /dev/null && command -v sops &> /dev/null; then
    run_test "Integration test" "nix-build tests/integration/test-sync.nix"
else
    echo -e "${YELLOW}⚠️  Skipping integration test (age/sops not available)${NC}"
fi

# Test 5: Example configurations
run_test "Basic example check" "nix flake check examples/basic"
run_test "Advanced example check" "nix flake check examples/advanced"

# Test 6: Package build
run_test "Package build" "nix build .#sopswarden-sync"

# Test 7: Development shell
run_test "Development shell" "nix develop --command echo 'Dev shell works'"

# Summary
echo -e "\n🏁 Test Summary:"
echo -e "${GREEN}✅ Tests passed: $TESTS_PASSED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}❌ Tests failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}🎉 All tests passed!${NC}"
fi