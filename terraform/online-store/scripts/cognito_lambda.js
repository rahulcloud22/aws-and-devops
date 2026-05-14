exports.handler = async (event) => {
  console.log("Pre-signup trigger invoked");
  console.log("Trigger source:", event.triggerSource);
  console.log("User pool ID:", event.userPoolId);
  console.log("Username:", event.userName);

  if (event.request && event.request.userAttributes) {
    console.log("User attributes:", {
      email: event.request.userAttributes.email,
      email_verified: event.request.userAttributes.email_verified,
    });
  }

  event.response.autoConfirmUser = true;
  event.response.autoVerifyEmail = true;
  // event.response.autoVerifyPhone = true;

  console.log("Auto-confirm and auto-verify flags set");

  return event;
};
