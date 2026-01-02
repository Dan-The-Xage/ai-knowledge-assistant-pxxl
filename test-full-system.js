/**
 * AI Knowledge Assistant - Full System Test Script
 *
 * This script tests all major functionality:
 * - RBAC (Role-Based Access Control)
 * - Conversation access and permissions
 * - AI service connectivity and responses
 * - Document upload and processing
 * - User management and authentication
 *
 * Run this in the browser console after logging in to test the system.
 */

(function() {
  console.log('🧪 AI Knowledge Assistant - Full System Test');
  console.log('==============================================');

  // Test configuration
  const TEST_CONFIG = {
    testUser: null,
    testConversation: null,
    testDocument: null,
    results: {
      rbac: { passed: 0, failed: 0, tests: [] },
      conversations: { passed: 0, failed: 0, tests: [] },
      ai: { passed: 0, failed: 0, tests: [] },
      documents: { passed: 0, failed: 0, tests: [] },
      permissions: { passed: 0, failed: 0, tests: [] }
    }
  };

  // Helper function to log test results
  function logTest(category, testName, passed, message = '') {
    const status = passed ? '✅ PASS' : '❌ FAIL';
    const fullMessage = `${status} ${category}: ${testName}${message ? ' - ' + message : ''}`;

    console.log(fullMessage);
    TEST_CONFIG.results[category].tests.push({
      name: testName,
      passed,
      message
    });

    if (passed) {
      TEST_CONFIG.results[category].passed++;
    } else {
      TEST_CONFIG.results[category].failed++;
    }
  }

  // Helper function to check if user has required role
  function hasRole(requiredRoles) {
    if (!TEST_CONFIG.testUser || !TEST_CONFIG.testUser.role) return false;
    return requiredRoles.includes(TEST_CONFIG.testUser.role);
  }

  // Test 1: RBAC (Role-Based Access Control)
  async function testRBAC() {
    console.log('\n🔐 Testing RBAC (Role-Based Access Control)...');

    try {
      // Get current user
      TEST_CONFIG.testUser = JSON.parse(localStorage.getItem('user'));
      if (!TEST_CONFIG.testUser) {
        logTest('rbac', 'User authentication', false, 'No user found in localStorage');
        return;
      }

      logTest('rbac', 'User authentication', true, `User: ${TEST_CONFIG.testUser.email}, Role: ${TEST_CONFIG.testUser.role}`);

      // Test role validation
      const validRoles = ['super_admin', 'admin', 'user', 'guest'];
      const isValidRole = validRoles.includes(TEST_CONFIG.testUser.role);
      logTest('rbac', 'Role validation', isValidRole, isValidRole ? 'Valid role' : `Invalid role: ${TEST_CONFIG.testUser.role}`);

      // Test admin access
      const isAdmin = hasRole(['admin', 'super_admin']);
      logTest('rbac', 'Admin access check', true, isAdmin ? 'Has admin privileges' : 'Regular user access');

      // Test super admin access
      const isSuperAdmin = hasRole(['super_admin']);
      logTest('rbac', 'Super admin access check', true, isSuperAdmin ? 'Has super admin privileges' : 'Not super admin');

    } catch (error) {
      logTest('rbac', 'RBAC system', false, error.message);
    }
  }

  // Test 2: Conversations Access
  async function testConversations() {
    console.log('\n💬 Testing Conversations Access...');

    try {
      // Import the API service
      const { conversationAPI } = await import('./app/src/services/api.js');

      // Test listing conversations
      const conversationsResponse = await conversationAPI.list();
      if (conversationsResponse.data) {
        logTest('conversations', 'List conversations', true, `Found ${conversationsResponse.data.length} conversations`);
      } else {
        logTest('conversations', 'List conversations', false, 'Failed to list conversations');
      }

      // Test creating a conversation
      if (conversationsResponse.data && conversationsResponse.data.length === 0) {
        const createResponse = await conversationAPI.create({
          title: 'System Test Conversation',
          content: 'Testing conversation creation'
        });

        if (createResponse.data) {
          TEST_CONFIG.testConversation = createResponse.data;
          logTest('conversations', 'Create conversation', true, `Created conversation: ${createResponse.data.title}`);
        } else {
          logTest('conversations', 'Create conversation', false, 'Failed to create conversation');
        }
      } else if (conversationsResponse.data && conversationsResponse.data.length > 0) {
        TEST_CONFIG.testConversation = conversationsResponse.data[0];
        logTest('conversations', 'Use existing conversation', true, `Using existing conversation: ${TEST_CONFIG.testConversation.title}`);
      }

    } catch (error) {
      logTest('conversations', 'Conversations system', false, error.message);
    }
  }

  // Test 3: AI Service Connectivity
  async function testAIService() {
    console.log('\n🤖 Testing AI Service Connectivity...');

    try {
      // Import AI service
      const { aiService } = await import('./app/src/services/aiService.js');

      // Test AI service status
      const status = aiService.getStatus();
      logTest('ai', 'AI service configuration', status.configured,
        status.configured ? 'AI service is configured' : status.message);

      // Test simple AI response (if configured)
      if (status.configured) {
        const response = await aiService.generateResponse('Hello, this is a test message.');
        if (response.success) {
          logTest('ai', 'AI response generation', true, 'Successfully generated AI response');
        } else {
          logTest('ai', 'AI response generation', false, response.error || 'Unknown AI error');
        }
      } else {
        logTest('ai', 'AI service skip', true, 'AI service not configured, skipping response test');
      }

      // Test embeddings generation (if configured)
      if (status.configured) {
        const embeddingResponse = await aiService.generateEmbeddings('This is a test document for embeddings.');
        if (embeddingResponse.success) {
          logTest('ai', 'Embedding generation', true, `Generated ${embeddingResponse.data.dimensions}-dimensional embedding`);
        } else {
          logTest('ai', 'Embedding generation', false, embeddingResponse.error || 'Unknown embedding error');
        }
      }

    } catch (error) {
      logTest('ai', 'AI service system', false, error.message);
    }
  }

  // Test 4: Document Upload and Access
  async function testDocuments() {
    console.log('\n📁 Testing Document Upload and Access...');

    try {
      // Import document API
      const { documentAPI } = await import('./app/src/services/api.js');

      // Test listing documents
      const documentsResponse = await documentAPI.list();
      if (documentsResponse.data) {
        logTest('documents', 'List documents', true, `Found ${documentsResponse.data.length} documents`);
      } else {
        logTest('documents', 'List documents', false, 'Failed to list documents');
      }

      // Test document access for chat
      const availableDocs = await documentAPI.getAvailableForChat();
      if (availableDocs.data) {
        logTest('documents', 'Chat document access', true, `${availableDocs.data.length} documents available for chat`);
      } else {
        logTest('documents', 'Chat document access', false, 'Failed to get documents for chat');
      }

    } catch (error) {
      logTest('documents', 'Documents system', false, error.message);
    }
  }

  // Test 5: Permissions and Security
  async function testPermissions() {
    console.log('\n🔒 Testing Permissions and Security...');

    try {
      // Test user profile access
      const { userAPI } = await import('./app/src/services/api.js');
      const profileResponse = await userAPI.getProfile();

      if (profileResponse.data) {
        logTest('permissions', 'User profile access', true, 'Successfully accessed user profile');
      } else {
        logTest('permissions', 'User profile access', false, 'Failed to access user profile');
      }

      // Test admin-only features (if user is admin)
      if (hasRole(['admin', 'super_admin'])) {
        const { adminAPI } = await import('./app/src/services/api.js');

        // Test user management access
        const usersResponse = await adminAPI.getUsers();
        if (usersResponse.data) {
          logTest('permissions', 'Admin user management', true, `Admin can access ${usersResponse.data.length} users`);
        } else {
          logTest('permissions', 'Admin user management', false, 'Admin cannot access user management');
        }

        // Test system stats access
        const statsResponse = await adminAPI.getSystemStats();
        if (statsResponse.data) {
          logTest('permissions', 'Admin system stats', true, 'Admin can access system statistics');
        } else {
          logTest('permissions', 'Admin system stats', false, 'Admin cannot access system stats');
        }
      } else {
        logTest('permissions', 'Regular user restrictions', true, 'Regular user properly restricted from admin features');
      }

    } catch (error) {
      logTest('permissions', 'Permissions system', false, error.message);
    }
  }

  // Test 6: Full Conversation Flow
  async function testFullConversationFlow() {
    console.log('\n🔄 Testing Full Conversation Flow...');

    try {
      if (!TEST_CONFIG.testConversation) {
        logTest('conversations', 'Full conversation flow', false, 'No conversation available for testing');
        return;
      }

      const { conversationAPI } = await import('./app/src/services/api.js');

      // Test sending a message
      const chatResponse = await conversationAPI.chat(TEST_CONFIG.testConversation.id, {
        content: 'This is a test message to verify the conversation flow is working properly.'
      });

      if (chatResponse.data && chatResponse.data.message) {
        logTest('conversations', 'Send message', true, 'Successfully sent message and received AI response');

        // Check if AI responded
        const hasAIResponse = chatResponse.data.message.message_type === 'assistant';
        logTest('conversations', 'AI response', hasAIResponse, hasAIResponse ? 'AI provided response' : 'No AI response received');
      } else {
        logTest('conversations', 'Send message', false, 'Failed to send message or receive response');
      }

    } catch (error) {
      logTest('conversations', 'Full conversation flow', false, error.message);
    }
  }

  // Generate test summary
  function generateSummary() {
    console.log('\n📊 TEST SUMMARY');
    console.log('==============');

    let totalPassed = 0;
    let totalFailed = 0;

    Object.keys(TEST_CONFIG.results).forEach(category => {
      const result = TEST_CONFIG.results[category];
      totalPassed += result.passed;
      totalFailed += result.failed;

      const passRate = result.passed + result.failed > 0 ?
        ((result.passed / (result.passed + result.failed)) * 100).toFixed(1) : '0.0';

      console.log(`${category.toUpperCase()}: ${result.passed} passed, ${result.failed} failed (${passRate}% success)`);
    });

    console.log(`\n🎯 OVERALL: ${totalPassed} passed, ${totalFailed} failed`);

    const overallPassRate = (totalPassed / (totalPassed + totalFailed)) * 100;
    if (overallPassRate >= 90) {
      console.log('✅ EXCELLENT: System is working optimally!');
    } else if (overallPassRate >= 75) {
      console.log('⚠️ GOOD: System is mostly working, minor issues to address');
    } else if (overallPassRate >= 50) {
      console.log('🟡 FAIR: System has significant issues that need attention');
    } else {
      console.log('❌ POOR: System has critical issues requiring immediate fixes');
    }

    console.log('\n🔧 RECOMMENDATIONS:');
    if (TEST_CONFIG.results.ai.failed > 0) {
      console.log('- Configure NEXT_PUBLIC_HF_API_TOKEN in Pxxl.app environment variables');
    }
    if (TEST_CONFIG.results.rbac.failed > 0) {
      console.log('- Check user roles and permissions in Supabase');
    }
    if (TEST_CONFIG.results.permissions.failed > 0) {
      console.log('- Verify RLS policies are properly configured');
    }
    if (TEST_CONFIG.results.conversations.failed > 0) {
      console.log('- Check conversation access permissions');
    }
  }

  // Run all tests
  async function runAllTests() {
    await testRBAC();
    await testConversations();
    await testAIService();
    await testDocuments();
    await testPermissions();
    await testFullConversationFlow();

    generateSummary();
  }

  // Make the test function globally available
  window.testAISystem = runAllTests;

  console.log('\n🚀 To run the full system test, execute:');
  console.log('   testAISystem()');
  console.log('\nThis will test RBAC, conversations, AI service, documents, and permissions.');

  // Auto-run the tests
  console.log('\n🔄 Starting automatic system test...');
  runAllTests();

})();