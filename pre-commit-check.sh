#!/bin/bash
# Pre-commit verification script for Wiz Exercise
# Run this before pushing to GitHub

echo "======================================"
echo "Pre-Commit Security Check"
echo "======================================"
echo ""

FAIL=0

echo "1. Checking for sensitive files..."
if git ls-files | grep -E '\.tfvars$|\.env$|.*key\.json$|credentials\.json$' | grep -v example; then
    echo "❌ FAIL: Sensitive files detected!"
    FAIL=1
else
    echo "✅ PASS: No sensitive files found"
fi
echo ""

echo "2. Checking for hardcoded passwords..."
if git grep -i -E 'password.*=.*["\047][^"\047]{8,}["\047]|api[_-]?key.*=.*["\047]|secret.*=.*["\047][^"\047]{8,}["\047]' -- '*.tf' '*.yml' '*.yaml' '*.sh' '*.go' 2>/dev/null; then
    echo "❌ FAIL: Possible hardcoded secrets found!"
    echo "Review the above matches carefully"
    FAIL=1
else
    echo "✅ PASS: No obvious hardcoded secrets"
fi
echo ""

echo "3. Checking for terraform.tfvars..."
if git ls-files | grep -E '^terraform/terraform\.tfvars$'; then
    echo "❌ FAIL: terraform.tfvars should not be committed!"
    echo "Use terraform.tfvars.example instead"
    FAIL=1
else
    echo "✅ PASS: terraform.tfvars not tracked"
fi
echo ""

echo "4. Checking for .env files..."
if git ls-files | grep -E '\.env$'; then
    echo "❌ FAIL: .env files should not be committed!"
    FAIL=1
else
    echo "✅ PASS: No .env files tracked"
fi
echo ""

echo "5. Checking for service account keys..."
if git ls-files | grep -E '.*-key\.json$|.*_key\.json$'; then
    echo "❌ FAIL: Service account keys detected!"
    FAIL=1
else
    echo "✅ PASS: No service account keys found"
fi
echo ""

echo "6. Checking for terraform state files..."
if git ls-files | grep -E '\.tfstate'; then
    echo "❌ FAIL: Terraform state files should not be committed!"
    FAIL=1
else
    echo "✅ PASS: No terraform state files"
fi
echo ""

echo "7. Checking for large files (>1MB)..."
LARGE_FILES=$(find . -type f -size +1M -not -path '*/\.git/*' 2>/dev/null)
if [ ! -z "$LARGE_FILES" ]; then
    echo "⚠️  WARNING: Large files detected:"
    echo "$LARGE_FILES"
    echo "Consider adding to .gitignore if not needed"
else
    echo "✅ PASS: No large files"
fi
echo ""

echo "8. Verifying critical files are present..."
REQUIRED_FILES=(
    "README.md"
    "terraform/main.tf"
    "terraform/variables.tf"
    "terraform/terraform.tfvars.example"
    "helm/todo-app/Chart.yaml"
    "docker/Dockerfile"
    "docker/wizexercise.txt"
    ".github/workflows/infra-deploy.yml"
    ".github/workflows/app-deploy.yml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "❌ MISSING: $file"
        FAIL=1
    fi
done
echo "✅ PASS: All critical files present"
echo ""

echo "======================================"
if [ $FAIL -eq 1 ]; then
    echo "❌ FAILED: Fix issues before committing!"
    echo "======================================"
    exit 1
else
    echo "✅ PASSED: Safe to commit!"
    echo "======================================"
    echo ""
    echo "Next steps:"
    echo "  git add ."
    echo "  git commit -m 'Initial Wiz technical exercise implementation'"
    echo "  git push origin main"
    exit 0
fi
