#!/usr/bin/env node

const { spawn, execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Colors for console output
const colors = {
	reset: '\x1b[0m',
	bright: '\x1b[1m',
	red: '\x1b[31m',
	green: '\x1b[32m',
	yellow: '\x1b[33m',
	blue: '\x1b[34m',
	magenta: '\x1b[35m',
	cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
	console.log(`${colors[color]}${message}${colors.reset}`);
}

function logStep(step, message) {
	log(`\n${colors.cyan}${step}${colors.reset} ${message}`, 'bright');
}

function logSuccess(message) {
	log(`✅ ${message}`, 'green');
}

function logError(message) {
	log(`❌ ${message}`, 'red');
}

function logWarning(message) {
	log(`⚠️  ${message}`, 'yellow');
}

function logInfo(message) {
	log(`ℹ️  ${message}`, 'blue');
}

// Check if Docker is running
function checkDocker() {
	try {
		execSync('docker --version', { stdio: 'ignore' });
		return true;
	} catch (error) {
		return false;
	}
}

// Check if Docker Compose is available
function checkDockerCompose() {
	try {
		execSync('docker-compose --version', { stdio: 'ignore' });
		return true;
	} catch (error) {
		try {
			execSync('docker compose version', { stdio: 'ignore' });
			return true;
		} catch (error) {
			return false;
		}
	}
}

// Get the appropriate docker-compose command
function getDockerComposeCommand() {
	try {
		execSync('docker-compose --version', { stdio: 'ignore' });
		return 'docker-compose';
	} catch (error) {
		try {
			execSync('docker compose version', { stdio: 'ignore' });
			return 'docker compose';
		} catch (error) {
			throw new Error('Neither docker-compose nor docker compose found');
		}
	}
}

// Check if docker-compose.yaml exists
function checkDockerComposeFile() {
	const composeFile = path.join(process.cwd(), 'docker-compose.yaml');
	if (!fs.existsSync(composeFile)) {
		throw new Error('docker-compose.yaml not found in current directory');
	}
}

// Run command and return promise
function runCommand(command, args = [], options = {}) {
	return new Promise((resolve, reject) => {
		const child = spawn(command, args, {
			stdio: 'inherit',
			shell: true,
			...options
		});

		child.on('close', (code) => {
			if (code === 0) {
				resolve();
			} else {
				reject(new Error(`Command failed with exit code ${code}`));
			}
		});

		child.on('error', (error) => {
			reject(error);
		});
	});
}

// Check if any of the service images exist
function checkServiceImages() {
	try {
		// Check if any of the service containers have been built
		const result = execSync('docker images --format "{{.Repository}}:{{.Tag}}" | grep open-webui', {
			stdio: 'pipe'
		}).toString();
		return result.trim().length > 0;
	} catch (error) {
		return false;
	}
}

// Check if a specific port is available
async function checkPort(port) {
	const host = 'localhost';
	const socket = require('net').createConnection(port, host);

	return new Promise((resolve) => {
		socket.on('connect', () => {
			socket.destroy();
			resolve(false); // Port is in use
		});
		socket.on('error', (err) => {
			if (err.code === 'ECONNREFUSED') {
				socket.destroy();
				resolve(true); // Port is available
			} else {
				socket.destroy();
				resolve(false); // Error occurred
			}
		});
	});
}

// Test service accessibility by attempting to connect to a port
async function testServiceAccess() {
	const ports = [3001, 3002, 3003];
	const results = [];

	for (const port of ports) {
		const available = await checkPort(port);
		results.push({ port, accessible: available });
	}

	return results;
}

// Main function
async function main() {
	try {
		log('🚀 Open WebUI Multi-Instance Starter', 'bright');
		log('=====================================\n', 'bright');

		// Pre-flight checks
		logStep('1', 'Checking prerequisites...');

		if (!checkDocker()) {
			throw new Error('Docker is not installed or not running');
		}
		logSuccess('Docker is available');

		if (!checkDockerCompose()) {
			throw new Error('Docker Compose is not available');
		}
		logSuccess('Docker Compose is available');

		checkDockerComposeFile();
		logSuccess('docker-compose.yaml found');

		const dockerComposeCmd = getDockerComposeCommand();
		logInfo(`Using: ${dockerComposeCmd}`);

		// Create default environment file if it doesn't exist
		const envFile = path.join(process.cwd(), '.env.prod');
		if (!fs.existsSync(envFile)) {
			logInfo('Creating default .env.prod file...');
			const defaultEnv = `# Open WebUI Configuration
# Add your configuration here
IONOS_SECURE_TOKEN=your-ionos-token-here

# Optional: Authentication
WEBUI_AUTH=false
`;
			fs.writeFileSync(envFile, defaultEnv);
			logSuccess('Created .env.prod file with default values');
			logWarning('Please edit .env.prod with your actual configuration values');
		} else {
			logSuccess('.env.prod file already exists');
		}

		// Load environment variables from .env.prod file
		logInfo('Loading environment variables from .env.prod...');
		try {
			const envContent = fs.readFileSync(envFile, 'utf8');
			const envLines = envContent.split('\n');

			envLines.forEach((line) => {
				const trimmedLine = line.trim();
				if (trimmedLine && !trimmedLine.startsWith('#')) {
					const [key, ...valueParts] = trimmedLine.split('=');
					if (key && valueParts.length > 0) {
						const value = valueParts.join('=');
						process.env[key.trim()] = value.trim();
					}
				}
			});
			logSuccess('Environment variables loaded successfully');
		} catch (error) {
			logWarning('Could not load environment variables from .env.prod');
		}

		// Check if images need to be built
		logStep('2', 'Checking existing images...');

		const imagesExist = checkServiceImages();

		if (imagesExist) {
			logSuccess('Service images exist - will use cached layers');
		} else {
			logWarning('No service images found - will build from scratch');
		}

		// Check if ports are available
		logStep('3', 'Checking port availability...');
		const ports = [3001, 3002, 3003];
		for (const port of ports) {
			const available = await checkPort(port);
			if (available) {
				logSuccess(`Port ${port} is available`);
			} else {
				logWarning(`Port ${port} might be in use`);
			}
		}

		// Build and start services
		logStep('4', 'Building Docker images...');

		logInfo('Building 3 Open WebUI images...');
		logInfo('This may take a few minutes on first run...');

		// Build images first
		await runCommand(dockerComposeCmd, ['build']);

		logSuccess('Images built successfully!');

		// Start services
		logStep('5', 'Starting Open WebUI instances...');

		logInfo('Starting 3 instances on ports 3001, 3002, 3003...');

		await runCommand(dockerComposeCmd, ['up', '-d']);

		logSuccess('All services started successfully!');

		// Wait a moment for services to fully start
		logStep('6', 'Waiting for services to initialize...');
		await new Promise((resolve) => setTimeout(resolve, 10000)); // Increased wait time

		// Show status
		logStep('7', 'Service Status...');
		await runCommand(dockerComposeCmd, ['ps']);

		// Check if services are actually running
		logStep('8', 'Verifying services are running...');
		try {
			const status = execSync(`${dockerComposeCmd} ps --format json`, { stdio: 'pipe' }).toString();
			const services = JSON.parse(`[${status.trim().replace(/\n/g, ',')}]`);

			let allRunning = true;
			services.forEach((service) => {
				if (service.State !== 'running') {
					logWarning(`Service ${service.Service} is not running (State: ${service.State})`);
					allRunning = false;
				} else {
					logSuccess(`Service ${service.Service} is running`);
				}
			});

			if (allRunning) {
				logSuccess('All services are running successfully!');
			} else {
				logWarning(
					'Some services may not be fully started yet. Check logs with: docker-compose logs'
				);
			}
		} catch (error) {
			logWarning('Could not verify service status, but continuing...');
		}

		// Test service accessibility
		logStep('9', 'Testing service accessibility...');
		try {
			const accessResults = await testServiceAccess();
			accessResults.forEach((result) => {
				if (result.accessible) {
					logSuccess(`Service on port ${result.port} is accessible`);
				} else {
					logWarning(`Service on port ${result.port} is not accessible yet`);
				}
			});
		} catch (error) {
			logWarning('Could not test service accessibility');
		}

		log('\n🎉 Open WebUI is ready!', 'green');
		log('=====================================', 'green');
		log('Instance 1: http://localhost:3001', 'cyan');
		log('Instance 2: http://localhost:3002', 'cyan');
		log('Instance 3: http://localhost:3003', 'cyan');
		log('\nUse "docker-compose logs -f" to view logs', 'yellow');
		log('Use "docker-compose down" to stop services', 'yellow');
	} catch (error) {
		logError(`Failed: ${error.message}`);
		process.exit(1);
	}
}

// Handle process termination
process.on('SIGINT', () => {
	log('\n\n⚠️  Received interrupt signal. Stopping services...', 'yellow');
	const dockerComposeCmd = getDockerComposeCommand();
	execSync(`${dockerComposeCmd} down`, { stdio: 'inherit' });
	log('Services stopped. Goodbye!', 'green');
	process.exit(0);
});

process.on('SIGTERM', () => {
	log('\n\n⚠️  Received termination signal. Stopping services...', 'yellow');
	const dockerComposeCmd = getDockerComposeCommand();
	execSync(`${dockerComposeCmd} down`, { stdio: 'inherit' });
	log('Services stopped. Goodbye!', 'green');
	process.exit(0);
});

// Run the main function
main();
