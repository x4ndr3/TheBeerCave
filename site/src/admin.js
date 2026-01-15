import {
    CognitoUserPool,
    CognitoUser,
    AuthenticationDetails
} from 'amazon-cognito-identity-js';

const poolData = {
    UserPoolId: import.meta.env.VITE_COGNITO_USER_POOL_ID,
    ClientId: import.meta.env.VITE_COGNITO_CLIENT_ID
};

const userPool = new CognitoUserPool(poolData);
const apiUrl = import.meta.env.VITE_API_URL;

const loginForm = document.getElementById('login-form');
const loginSection = document.getElementById('login-section');
const dashboardSection = document.getElementById('dashboard-section');
const loginError = document.getElementById('login-error');
const messagesList = document.getElementById('messages-list');
const logoutBtn = document.getElementById('logout-btn');

// Check if user is already logged in
let currentUser = userPool.getCurrentUser();
if (currentUser) {
    currentUser.getSession((err, session) => {
        if (session && session.isValid()) {
            showDashboard(session);
        }
    });
}

loginForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const email = document.getElementById('login-email').value;
    const password = document.getElementById('login-password').value;

    const authData = {
        Username: email,
        Password: password
    };
    const authDetails = new AuthenticationDetails(authData);
    const userData = {
        Username: email,
        Pool: userPool
    };
    const cognitoUser = new CognitoUser(userData);

    const submitBtn = loginForm.querySelector('button');
    submitBtn.disabled = true;
    submitBtn.textContent = 'Authenticating...';
    loginError.textContent = '';

    cognitoUser.authenticateUser(authDetails, {
        onSuccess: (result) => {
            showDashboard(result);
        },
        onFailure: (err) => {
            loginError.textContent = err.message || JSON.stringify(err);
            submitBtn.disabled = false;
            submitBtn.textContent = 'Initialize session';
        }
    });
});

logoutBtn.addEventListener('click', () => {
    const cognitoUser = userPool.getCurrentUser();
    if (cognitoUser) {
        cognitoUser.signOut();
        window.location.reload();
    }
});

async function showDashboard(session) {
    loginSection.style.display = 'none';
    dashboardSection.style.display = 'block';

    const idToken = session.getIdToken().getJwtToken();
    fetchMessages(idToken);
}

async function fetchMessages(token) {
    try {
        const response = await fetch(`${apiUrl}/messages`, {
            headers: {
                'Authorization': token
            }
        });

        if (!response.ok) throw new Error('Failed to fetch messages');

        const messages = await response.json();
        renderMessages(messages);
    } catch (err) {
        messagesList.innerHTML = `<p style="color: red;">Error: ${err.message}</p>`;
    }
}

function renderMessages(messages) {
    if (messages.length === 0) {
        messagesList.innerHTML = '<p>No messages found in the archives.</p>';
        return;
    }

    messagesList.innerHTML = messages.map(msg => `
        <div class="message-card">
            <div class="message-header">
                <span>From: ${msg.email}</span>
                <span>${new Date(msg.timestamp || Date.now()).toLocaleString()}</span>
            </div>
            <div class="message-body">
                <p><strong>Name:</strong> ${msg.name}</p>
                <p style="margin-top: 0.5rem;">${msg.message}</p>
            </div>
        </div>
    `).join('');
}
