import axios from 'axios'
import Keycloak from 'keycloak-js'

let realm = "lilypad"
console.log(`Using realm ${realm}`)

const keycloakUrl = `/auth/`
console.log(`Constructed keycloak url as: ${keycloakUrl}`)

const _kc = new Keycloak({
  "realm": realm,
  "url": keycloakUrl,
  "clientId": "frontend"
});

// every http request that we hit the server with
// needs to ask keycloak - what is my current token?
const jwtInterceptor: any = (config: any) => {
  if (isLoggedIn()) {
    const cb = () => {
      config.headers.Authorization = `Bearer ${getToken()}`;
      return Promise.resolve(config);
    };
    return UserService.updateToken(cb);
  }
  return config
}

axios.interceptors.request.use(jwtInterceptor)

/**
 * Initializes Keycloak instance and calls the provided callback function if successfully authenticated.
 *
 * @param onAuthenticatedCallback
 */
const initKeycloak = (onAuthenticatedCallback: any) => {
  _kc.init({
    onLoad: 'check-sso',
    // silentCheckSsoRedirectUri: window.location.origin + '/silent-check-sso.html',
    pkceMethod: 'S256',
  })
    .then((authenticated: any) => {
      if (authenticated) {
        _kc.loadUserProfile()
          .then(function(profile: any) {
            // rudderanalytics.identify(profile.email, profile, () => {
            // });
          }).catch(function() {
              //alert('Failed to load user profile')
          })
        
        onAuthenticatedCallback()
      } else {
        doLogin()
      }
    })
};

const doLogin = _kc.login;

const doLogout = () => {
  _kc.logout();
}

const getToken = () => _kc.token;

const isLoggedIn = () => !!_kc.token;

const updateToken = (successCallback: any) =>
  _kc.updateToken(5)
    .then(successCallback)
    .catch(doLogin);

const getUsername = () => _kc.tokenParsed?.preferred_username;
const getProfile = () => _kc.tokenParsed;

const hasRole = (roles: any) => roles.some((role: any) => _kc.hasRealmRole(role));

const UserService = {
  initKeycloak,
  doLogin,
  doLogout,
  isLoggedIn,
  getToken,
  updateToken,
  getUsername,
  getProfile,
  hasRole,
};

export default UserService;