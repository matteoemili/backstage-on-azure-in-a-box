import { createApp } from '@backstage/frontend-defaults';
import { createFrontendModule } from '@backstage/frontend-plugin-api';
import { SignInPageBlueprint } from '@backstage/plugin-app-react';
import catalogPlugin from '@backstage/plugin-catalog/alpha';
import { navModule } from './modules/nav';
import { SignInPage } from '@backstage/core-components';
import {
  microsoftAuthApiRef,
  githubAuthApiRef,
  type SignInPageProps,
} from '@backstage/core-plugin-api';

const signInPage = SignInPageBlueprint.make({
  params: {
    loader: async () => (props: SignInPageProps) =>
      (
        <SignInPage
          {...props}
          auto
          providers={[
            'guest',
            {
              id: 'microsoft-auth-provider',
              title: 'Microsoft',
              message: 'Sign in using Entra ID',
              apiRef: microsoftAuthApiRef,
            },
            {
              id: 'github-auth-provider',
              title: 'GitHub',
              message: 'Sign in using GitHub',
              apiRef: githubAuthApiRef,
            },
          ]}
        />
      ),
  },
});

const signInModule = createFrontendModule({
  pluginId: 'app',
  extensions: [signInPage],
});

export default createApp({
  features: [catalogPlugin, navModule, signInModule],
});