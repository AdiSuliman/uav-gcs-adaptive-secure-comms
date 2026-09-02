/* Include files */

#include "UAV_GCS_Base_Link_cgxe.h"
#include "m_g8KMDM2oJbDB6PvVUPa2vF.h"

unsigned int cgxe_UAV_GCS_Base_Link_method_dispatcher(SimStruct* S, int_T method,
  void* data)
{
  if (ssGetChecksum0(S) == 2716050094 &&
      ssGetChecksum1(S) == 3981869037 &&
      ssGetChecksum2(S) == 3137263383 &&
      ssGetChecksum3(S) == 1437230) {
    method_dispatcher_g8KMDM2oJbDB6PvVUPa2vF(S, method, data);
    return 1;
  }

  return 0;
}
