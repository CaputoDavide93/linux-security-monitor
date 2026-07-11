# Contributing to Linux Security Monitor

Thank you for your interest in contributing! 🎉

## 🚀 Quick Start

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/YOUR_USERNAME/EC2-Linux-Security-Monitor.git`
3. **Create** a branch: `git checkout -b feature/your-feature`
4. **Make** your changes
5. **Test** on multiple distros
6. **Commit**: `git commit -m 'Add feature'`
7. **Push**: `git push origin feature/your-feature`
8. **Open** a Pull Request

## 📋 Guidelines

### Code Style

- Follow shell script best practices
- Use `shellcheck` for linting
- Add comments for complex logic
- Use meaningful variable names
- Quote all variables: `"$var"` not `$var`

### Testing

Before submitting:

```bash
# Run shellcheck
shellcheck security-monitor.sh security-manager.sh

# Validate syntax
bash -n security-monitor.sh && bash -n security-manager.sh

# Test on multiple distributions if possible
```

### Commit Messages

```
type(scope): description

[optional body]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## 🐛 Bug Reports

Please include:
- Linux distribution and version
- Bash version (`bash --version`)
- Error messages
- Steps to reproduce
- Expected vs actual behavior

## 💡 Feature Requests

Open an issue with:
- Clear description
- Use case
- Security benefit
- Example implementation (if any)

## 🔒 Security Considerations

When contributing security checks:

1. Ensure checks are accurate (no false positives)
2. Provide remediation guidance
3. Test on multiple distributions
4. Consider performance impact
5. Document severity levels

## 📝 Pull Request Process

1. Update documentation if needed
2. Add tests for new features
3. Ensure shellcheck passes
4. Test on at least 2 Linux distributions
5. Request review from maintainers

---

Thank you for contributing! 🙏
