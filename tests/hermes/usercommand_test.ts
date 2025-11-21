// User Command API Tests - TypeScript
// Tests vim.api.createUserCommand() and related functions
// Neovim-compatible with TypeScript type safety
//
// Build: zig build hermes-tests

declare const vim: {
    api: {
        createUserCommand: <Opts extends UserCommandOpts>(
            name: string,
            callback: (args: InferCommandArgs<Opts>) => void,
            opts?: Opts
        ) => void;
        delUserCommand: (name: string) => void;
        bufCreateUserCommand: <Opts extends UserCommandOpts>(
            buffer: number,
            name: string,
            callback: (args: InferCommandArgs<Opts>) => void,
            opts?: Opts
        ) => void;
        bufDelUserCommand: (buffer: number, name: string) => void;
        getUserCommands: (opts?: { builtin?: boolean }) => Array<{
            name: string;
            definition: string;
            nargs: string;
            range: string;
            complete: string;
            bang: boolean;
            bar: boolean;
            register: boolean;
            buffer: number;
        }>;
    };
    test: {
        assert: (condition: boolean, message?: string) => void;
        assertEqual: <T>(actual: T, expected: T, message?: string) => void;
        pass: (name: string) => void;
        fail: (name: string, error: string) => void;
    };
};

// Type definitions for type inference
interface CommandArgsBase {
    name: string;
    args: string;
    fargs: string[];
    bang: boolean;
    mods: string;
}

interface CommandRangeArgs {
    line1: number;
    line2: number;
    range: 0 | 1 | 2;
}

interface CommandCountArgs {
    count: number;
}

interface CommandRegisterArgs {
    reg: string;
}

interface UserCommandOpts {
    desc?: string;
    bang?: boolean;
    bar?: boolean;
    force?: boolean;
    range?: boolean | '%' | number;
    count?: number;
    register?: boolean;
    nargs?: '0' | '1' | '*' | '?' | '+';
    complete?: string | ((argLead: string, cmdLine: string, cursorPos: number) => string[]);
}

type InferCommandArgs<Opts extends UserCommandOpts> = CommandArgsBase
    & (Opts extends { range: any } ? CommandRangeArgs : {})
    & (Opts extends { count: number } ? CommandCountArgs : {})
    & (Opts extends { register: true } ? CommandRegisterArgs : {});

// Test 1: Basic command creation
function test_create_basic_command() {
    let callbackCalled = false;

    vim.api.createUserCommand('Greet', (args) => {
        callbackCalled = true;
        // Type check: args should have base properties
        vim.test.assert(typeof args.name === 'string', 'args.name should be string');
        vim.test.assert(typeof args.args === 'string', 'args.args should be string');
        vim.test.assert(Array.isArray(args.fargs), 'args.fargs should be array');
        vim.test.assert(typeof args.bang === 'boolean', 'args.bang should be boolean');
        vim.test.assert(typeof args.mods === 'string', 'args.mods should be string');
    });

    // Should not throw
    vim.test.pass('test_create_basic_command');
}

// Test 2: Command with description
function test_create_command_with_desc() {
    vim.api.createUserCommand('Documented', (args) => {
        // noop
    }, {
        desc: 'A well-documented command'
    });

    vim.test.pass('test_create_command_with_desc');
}

// Test 3: Command with range option (type inference test)
function test_create_command_with_range() {
    vim.api.createUserCommand('Format', (args) => {
        // TypeScript should infer that args has line1, line2, range
        vim.test.assert(typeof args.line1 === 'number', 'args.line1 should be number');
        vim.test.assert(typeof args.line2 === 'number', 'args.line2 should be number');
        vim.test.assert(typeof args.range === 'number', 'args.range should be number');
    }, { range: '%' });

    vim.test.pass('test_create_command_with_range');
}

// Test 4: Command with register option (type inference test)
function test_create_command_with_register() {
    vim.api.createUserCommand('YankTo', (args) => {
        // TypeScript should infer that args has reg
        vim.test.assert(typeof args.reg === 'string', 'args.reg should be string');
    }, { register: true });

    vim.test.pass('test_create_command_with_register');
}

// Test 5: Command with multiple options
function test_create_command_with_all_options() {
    vim.api.createUserCommand('Complex', (args) => {
        // Has all optional fields due to options
        vim.test.assert(typeof args.name === 'string', 'args.name exists');
        vim.test.assert(typeof args.line1 === 'number', 'args.line1 exists');
        vim.test.assert(typeof args.reg === 'string', 'args.reg exists');
    }, {
        desc: 'Complex command',
        bang: true,
        bar: true,
        range: '%',
        register: true,
        nargs: '*'
    });

    vim.test.pass('test_create_command_with_all_options');
}

// Test 6: Delete user command
function test_del_user_command() {
    vim.api.createUserCommand('ToDelete', () => {});

    // Should not throw
    vim.api.delUserCommand('ToDelete');

    // Deleting again should be idempotent (no error)
    vim.api.delUserCommand('ToDelete');

    vim.test.pass('test_del_user_command');
}

// Test 7: Buffer-local command creation
function test_buf_create_user_command() {
    vim.api.bufCreateUserCommand(0, 'BufferCmd', (args) => {
        vim.test.assert(typeof args.name === 'string', 'args.name should be string');
    });

    vim.test.pass('test_buf_create_user_command');
}

// Test 8: Buffer-local command deletion
function test_buf_del_user_command() {
    vim.api.bufCreateUserCommand(0, 'ToDeleteBuf', () => {});

    // Should not throw
    vim.api.bufDelUserCommand(0, 'ToDeleteBuf');

    // Deleting again should be idempotent
    vim.api.bufDelUserCommand(0, 'ToDeleteBuf');

    vim.test.pass('test_buf_del_user_command');
}

// Test 9: Get user commands list
function test_get_user_commands() {
    // Create a command first
    vim.api.createUserCommand('ListTest', () => {}, { desc: 'For listing' });

    const commands = vim.api.getUserCommands();

    vim.test.assert(Array.isArray(commands), 'getUserCommands should return array');

    // Find our command
    const found = commands.find(cmd => cmd.name === 'ListTest');
    vim.test.assert(found !== undefined, 'Should find ListTest command');

    if (found) {
        vim.test.assert(typeof found.name === 'string', 'command.name should be string');
        vim.test.assert(typeof found.bang === 'boolean', 'command.bang should be boolean');
        vim.test.assert(typeof found.bar === 'boolean', 'command.bar should be boolean');
        vim.test.assert(typeof found.register === 'boolean', 'command.register should be boolean');
        vim.test.assert(typeof found.buffer === 'number', 'command.buffer should be number');
    }

    vim.test.pass('test_get_user_commands');
}

// Test 10: Command with nargs options
function test_command_nargs_options() {
    // No arguments
    vim.api.createUserCommand('NoArgs', () => {}, { nargs: '0' });

    // Exactly one argument
    vim.api.createUserCommand('OneArg', () => {}, { nargs: '1' });

    // Any number of arguments
    vim.api.createUserCommand('AnyArgs', () => {}, { nargs: '*' });

    // Zero or one argument
    vim.api.createUserCommand('OptionalArg', () => {}, { nargs: '?' });

    // One or more arguments
    vim.api.createUserCommand('ManyArgs', () => {}, { nargs: '+' });

    vim.test.pass('test_command_nargs_options');
}

// Test 11: Force overwrite existing command
function test_force_overwrite() {
    vim.api.createUserCommand('Overwrite', () => {});

    // Should succeed with force: true
    vim.api.createUserCommand('Overwrite', () => {}, { force: true });

    vim.test.pass('test_force_overwrite');
}

// Run all tests
function runTests() {
    test_create_basic_command();
    test_create_command_with_desc();
    test_create_command_with_range();
    test_create_command_with_register();
    test_create_command_with_all_options();
    test_del_user_command();
    test_buf_create_user_command();
    test_buf_del_user_command();
    test_get_user_commands();
    test_command_nargs_options();
    test_force_overwrite();
}

runTests();
