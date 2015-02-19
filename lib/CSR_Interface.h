#ifndef CSR_INTERFACE_H
#define CSR_INTERFACE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CSR_Handle CSR_Handle;
CSR_Handle *CSR_Create(int numRows, int numCols, int *i, int *j, double *v);
void CSR_MultiplyWithVector(const CSR_Handle *A, double *y, const double *x);
void CSR_GetRCMPemutation(const CSR_Handle *A, int *perm, int *inversePerm);
void CSR_Permute(const CSR_Handle *A, CSR_Handle *out, const int *columnPerm, const int *rowInversePerm);
int CSR_GetBandwidth(CSR_Handle *A);
void CSR_PrintInDense(CSR_Handle *A);
void CSR_Destroy(CSR_Handle *A);

#ifdef __cplusplus
}
#endif

#endif // CSR_INTERFACE_H
